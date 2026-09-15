# Status: PostgreSQL → CloudNativePG

Living log of gates passed and open decisions. Update at every phase boundary.

## 2026-09-15 — Phases 0–3 prepared, nothing deployed yet

### Phase 0 — Prerequisites
| Gate | State | Notes |
|---|---|---|
| 0.1 Pi MinIO | **GREEN** | `backup-pool` needed `zpool import -F` rewind again (same failure as 2026-08; unit failed since 2026-09-07). Pool ONLINE, 462G used / 438G free, MinIO `/minio/health/live` = 200, scrub started 12:09. |
| 0.2 Backup pipeline | in progress | First manual `postgres-backup` job failed with its pod GC'd (no logs); rerun with log streaming. Restore drill still to run after a good dump. |
| 0.3 Ceph capacity | **RED, user decision** | `replicapool` MAX AVAIL 5.9 GiB (need ≥ 60). Root cause: `osd.0` (lab-delta-cp nvme, 416G) at 94 % while `osd.1` (lab-alpha-cp ssd, 932G) sits at 54 % with 425 GiB free; balancer refuses to run while PGs are degraded. See options below. |
| 0.4 Access | **GREEN** | context `ze-homelab`; NetworkPolicy `postgresql-18` allows ingress on 5432 from any namespace (no `from` selector). |

**Ceph options (numbers measured 2026-09-15, nothing changed):**
1. `valoris-s3` RGW bucket: 380 GiB stored in the EC pool `ceph-objectstore.rgw.buckets.data` (590 GiB raw). Deliberately unbacked-up. Deleting it frees the most space on every OSD.
2. Seven `Released` PVs (reclaim Retain, orphans): rabbitmq 0.4 GiB, omniroute-data 4.9, omniroute-data-home 0.03, immich-machine-learning 1.8, grafana 1.4, old `data-postgresql-0` 8.5, readeck (image already gone) ≈ 17 GiB stored / 51 GiB raw.
3. RBD snapshot on the postgres volume from 2026-01-29: 3.5 GiB.
4. Rebalance instead of delete: `osd.0` is the constraint; lowering its weight (`ceph osd reweight osd.0 <0.85..0.9>`) or a CRUSH reweight pushes PGs to the half-empty ssd OSDs. Non-destructive but triggers backfill on a cluster already showing slow ops and stalled BlueFS reads.
5. Add an OSD on lab-delta-cp / lab-alpha-cp.

### Phase 1 — Safety-net dump — **GREEN**
- `~/pg-migration/pre-cnpg-2026-09-15.sql.zst` (1.8 GB, `pg_dumpall` from PG 18.4 client over LAN, 7 min) + per-DB `-Fc` dumps for valoris_production, synapse, hindsight, n8n, immich. `SHA256SUMS` alongside.
  Stored on the workstation NVMe, **not** on CephFS (`~/Homelab` has 6 GB free and is itself Ceph).
- `inventory-source-2026-09-15.txt`: 79 databases, 2 roles (`postgres`, `immich`), 1251 tables (exact counts), sequences, index/constraint counts.
- Restored the full dump twice into the Phase 2 image (6 min each): 0 FATAL/PANIC, the only ERROR is `role "postgres" already exists` (expected).
- `scripts/pg-inventory-diff.sh` source vs restored: **0 objects missing**; 17 table counts and 19 sequences drifted (live writes between dump and inventory in queue/event tables); extensions moved upward only (vchord 0.5.3→1.1.1, vector 0.8.1→0.8.6, postgis 3.6.1→3.6.4). Files: `inventory-restored-2026-09-15.txt`, `inventory-diff.txt`.

### Phase 2 — Custom image — **GREEN**
See [image.md](./image.md). `ghcr.io/josevictorferreira/postgresql-cnpg:18.6-vchord1.1.1-postgis3@sha256:5b3c66d1…` (private).

### Phase 3 — Nix (written, `make manifests` green, **not committed**)
- `config/kubernetes.nix`: namespace `databases`.
- `bootstrap/resource-quotas.nix`: quota 1/3Gi requests, 4/8Gi limits; LimitRange default 250m/256Mi, max 2/6Gi. Needs a NixOS deploy of `lab-alpha-cp` (k3s addon controller).
- `_crds.nix`: `cluster`, `database`, `scheduledbackup`, `backup` (postgresql.cnpg.io/v1), `objectstore` (barmancloud.cnpg.io/v1), plus cert-manager `issuer` (the barman chart renders one).
- `databases/cloudnative-pg.nix` (chart 0.29.0 → operator 1.30.0), `databases/plugin-barman-cloud.nix` (chart 0.8.0 → v0.15.0), `databases/ghcr-registry-secret.enc.nix`, `databases/postgresql-secrets.enc.nix` (`postgresql-superuser` basic-auth, `postgresql-backup-s3`). The import source reuses `postgresql-superuser` instead of a separate secret.
- `_lib.postgresHost` added, unused until Phase 5.
- Disabled (leading `_`): `databases/_postgresql-lib.nix` (shared spec), `_postgresql-rehearsal.nix` (Phase 4), `_postgresql.nix` (Phase 5: barman plugin, ObjectStore `pi-minio` → `s3://homelab-backup-postgres/cnpg/`, ScheduledBackup `0 30 5 * * *` UTC = 02:30 BRT, one `Database` CR per entry in `homelab.kubernetes.databases.postgres`, LB service `postgresql-lb`).
- Side effect in `.k8s/system/cert-manager.yaml`: cert-manager.nix issues the wildcard Certificate into the new namespace (expected).

### Deviations from plan.md
- Dump compressed with `zstd -10` instead of `-19` (speed); restore test done on the custom image (superset of the plan's two checks).
- No separate `postgresql-import-source` secret.
- ScheduledBackup uses UTC (CNPG has no timezone field).
- Containerfile lives in this repo (`oci-images/postgresql-cnpg/`) and is built with podman, not in a separate GitHub repo.

### Incident 2026-09-15 12:22–12:3x BRT — postgresql-18 killed by liveness probe during the manual backup job
- The manual `postgres-backup` job (in-cluster `pg_dumpall`) ran 12:10–12:22. `COPY` of the valoris event tables took 108 s and 169 s; ordinary app statements then took 60–150 s (`solid_queue`, Grafana annotation inserts), `pg_isready` timed out 6× and kubelet sent a smart shutdown at 15:22:03 GMT, then SIGKILL at 15:25:50 (exit 137). Crash recovery from the 15:00 checkpoint followed.
- Not new: the pod had 43 liveness failures / 4 restarts in the previous 2 days without any manual job.
- Storage is the bottleneck: `ceph osd perf` shows `osd.1` (lab-alpha-cp, **Crucial BX500 1 TB**, DRAM-less consumer SSD) at 450–2700 ms commit latency while osd.0/osd.4 sit at 5–20 ms. Every `replicapool` write (size 3) waits for osd.1. Ceph also reports `BLUESTORE_SLOW_OP_ALERT` and `DB_DEVICE_STALLED_READ` for osd.1, and lab-alpha-cp logged hung tasks on 2026-09-12.
- Consequence for this plan: the CNPG import (Phase 4/5) is the same read pattern as `pg_dumpall` plus a full write of ~20 GB into the same pool. **Do not start Phase 4 until osd.1 latency is addressed**, or accept that the source instance may be liveness-killed during the import (the import job itself would then fail and need a retry). Also reconsider the `postgresql-18` liveness probe (`pg_isready` 5 s timeout × 6) which turns storage stalls into outages; see memory `postgres-recovery-liveness-deadlock`.
- The in-cluster backup job was **not** rerun after the kill (it would repeat the stall). Gate 0.2 therefore stays open. The workstation dump from Phase 1 is verified and is the current safety net.

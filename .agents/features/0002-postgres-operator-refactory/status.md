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

### Phase 3 — Nix — **GREEN** (commit `9c478b66`, Flux applied 12:55 BRT)
Gate checked 12:57: namespace Active, ResourceQuota + LimitRange present, `cloudnative-pg` and `plugin-barman-cloud` pods Running (one restart each from a lab-gamma-wk sandbox blip, plugin re-registered), 4 CRDs, 3 secrets with the right types, barman client/server Certificates Ready. `make reconcile` itself failed (attic cache 500 while fetching the command derivation), Flux picked the commit up on its own. NixOS deploy of lab-alpha-cp for the k3s bootstrap copy of the quota: see below.
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

### Incident 2026-09-15 12:51– BRT — lab-gamma-wk reboot loop (pre-existing gk3v issue)
- Boots at 12:51:52, 12:54:15, 12:56:14, 12:57:36; journals end mid-activity (hard reset, no shutdown message). `x86_pkg_temp` reads 100 °C one minute after boot with the 10 W RAPL cap in place. See memory `gamma-gk3v-reboot-loops-two-causes`.
- Effect: osd.3 and osd.5 down, `ceph-bluestore-tool` ABRT during OSD activation on one boot, CephFS "No mds server is up", 28 % objects degraded. The CNPG operator + barman plugin pods were scheduled on gamma (2 sandbox restarts, healthy afterwards). Consider a soft anti-affinity away from lab-gamma-wk for the operator pods.
- NixOS deploy of lab-alpha-cp (k3s bootstrap copy of the `databases` quota) **deferred**: Flux already applied the quota, and k3s's addon controller only manages its own objectset, so nothing reverts it. Do the deploy (memory `deploy-rs-broken-use-copy-switch`) once Ceph is HEALTH_OK-ish.
- Phase 4 stays blocked: Ceph capacity (0.3), osd.1 latency, and now degraded redundancy.

### 2026-09-15 13:00–14:30 BRT — cluster recovery actions (user asked to fix everything; `valoris-s3` must stay)
- **Gamma**: RAPL 6 W/8 W cap + no_turbo + 1.5 GHz clamp applied at runtime, then made durable (`hosts/hardware/intel-nuc-gk3v.nix`, commit `a52d5c58`, deployed 13:26). Stable at 74–80 °C since 13:22 with k3s running. Still needs physical cooler service.
- **Availability**: 22 replicapool PGs and 2 CephFS PGs were `peered` (single copy on osd.1, backfill_toofull elsewhere). Set `min_size 1` on `replicapool` and `ceph-filesystem-data0` **temporarily**; `noout` set. **Restore `min_size 2` and unset `noout` once osd.3 is rebuilt and recovery finishes.**
- **Workloads**: force-deleted pods stranded on gamma; all app pods Running again by 13:35. Crash loops (bookorbit/glyph/wealtho/valoris-worker/redis/grafana) were all Postgres-down or storage-stall symptoms.
- **Space (no live data deleted)**: `fstrim` on every mounted RBD volume returned ~160 GiB (one 100 Gi volume had 97 GiB of dead blocks); purged 9 expired RBD trash images (94 GiB provisioned, needed `rbd snap purge --image-id` first); deleted two orphan images with user approval: old `monitoring` Prometheus TSDB (`csi-vol-9e914f7d…`, 48 GiB + two 24 GiB snapshots, from the pre-May-2026 cluster) and the abandoned OpenClaw RBD state copy (`csi-vol-75b04aa8…`, 15 Gi). replicapool stored 258 → 186 GiB so far. Still orphaned: `csi-vol-77cee549…` (1 Gi mautrix config, `apps`), 7 Released PVs (~17 GiB), 2026-01-29 snapshots on live images.
- **osd.3** (gamma SSD): BlueFS allocator corrupt after the reset storm (`AvlAllocator::init_rm_free` assert in `BlueFS::mount`, both in `expand-bluefs` and in `ceph-bluestore-tool repair`). Verified 0 unfound / no down PGs, then `ceph osd purge 3`, `blkdiscard` + `wipefs` on `/dev/disk/by-partlabel/CEPH_OSD_NVME` (label `whoami: 3` checked first), deleted the deployment and prepare jobs, operator re-provisioning.
- **Device-name flip on gamma**: HDD is now `sda`, SSD `sdb`; Rook still pins osd.5 to `/dev/sdb1` (the EFI partition). It only started because the activate fallback rescanned. Durable fix still open (see memory `rook-osd-block-path-goes-stale`).
- **pg 12.75** (RGW EC) inconsistent with 74 shards missing on osd.5: `ceph pg repair 12.75` issued.
- **Flux** is **suspended** (`kubectl patch kustomization flux-system … suspend=true`) so it stops rescaling the Rook operator while osd.3 is handled. **Resume when osd.3 is up.**
- Repair pod `osd3-repair` (privileged, on gamma, contained the admin keyring) was deleted.

### 2026-09-15 15:15 BRT — end state
- All 6 OSDs up (osd.3 SSD and osd.5 HDD on gamma rebuilt from scratch: osd.3 had an unrepairable BlueFS allocator assert, osd.5 RocksDB SST checksum corruption; no unfound objects at any point). Recovery/backfill onto gamma running (~2.7 M objects degraded at start, 26 MiB/s). Expect hours.
- `~/pg-migration/ceph-restore-replication.sh` runs in the background (log next to it) and, once `ceph pg stat` shows no degraded/undersized/backfill PGs with 6 OSDs up, sets `min_size 2` on `replicapool` and `ceph-filesystem-data0`, unsets `noout`, and resumes the Flux kustomization. Until then those three emergency settings are in effect and **Flux is suspended**.
- Gamma: durable 6 W cap + 1.5 GHz clamp, 70–80 °C, stable since the 14:53 boot (WoL from the Pi worked). Device names flipped again on that boot (SSD=`sda3`, HDD=`sdb1`); new OSD deployments were created with the current names. Physical cooler service still required; until then any reboot can flip names again.
- Space: replicapool 258 → 179 GiB stored; osd.0 (delta) still 94 % until the balancer runs after recovery. Structural limit unchanged: alpha can hold only 1/3 of raw data, so effective capacity ≈ 3 × min(beta, delta, gamma).
- Open: standby MDS `ceph-filesystem-a` Pending (CPU requests saturated on alpha/beta, memory on delta, anti-affinity elsewhere); `postgres-backup` gate 0.2 not rerun (wait for recovery to finish); Postgres liveness probe still `pg_isready` 5 s × 6; alpha NixOS deploy for the bootstrap quota pending; migration Phase 4 blocked until Ceph is HEALTH_OK with ≥ 60 GiB MAX AVAIL.

### 2026-09-16 05:40 BRT — recovery deadlock broken
- Overnight backfill stalled at 5.6 % degraded: all 69 remaining PGs were `backfill_toofull` waiting on osd.0 (delta, 93.75 %, above the 0.90 backfillfull ratio), and osd.0 could not drop its stale copies until those PGs finished elsewhere. Balancer refuses to run while degraded → deadlock.
- Fix: `ceph osd reweight osd.0 0.85` (override weight, not CRUSH weight) → PGs re-targeted to beta/gamma OSDs with room; backfill resumed within a minute (60 blocked → 4). Revert to 1.0 once the balancer has run, or leave if delta stays the fullest host.
- mClock profile set back to `balanced` (from `high_recovery_ops`): with recovery prioritized, Postgres checkpoints took 15–19 min and it was liveness-killed once more at 04:12 BRT despite the 3-min budget.
- gamma stayed up all night on the 4 W / 1.2 GHz runtime cap (14.7 h); the durable NixOS unit still has 6 W / 1.5 GHz.
- `ceph-restore-replication.sh` hung on a kubectl exec (log frozen at 23:35); restarted with `timeout 120` around every ceph call and `setsid`, so it survives session teardown.

### 2026-09-16 09:09–09:25 BRT — Phase 4 attempt aborted (control-plane outage)
- Started the rehearsal import on user request while Ceph was still 5.5 % degraded (reasoning: osd.0 was in no acting set, so new RBD writes would not land on it). Correct on capacity, wrong on load: within 3 minutes osd.4 (beta, NVMe shared with beta's ZFS root and etcd) hit 2.8 s commit latency, beta's ZFS `txg_sync` went D-state, etcd lost its leader, k3s restarted on alpha (×2) and delta (×3), the API returned 503/etcd timeouts.
- Recovery: import containers could not be stopped via the API; found on beta; `echo b > /proc/sysrq-trigger` on beta (memory `storage-node-down-cascades-controlplane-outage`), API back in 30 s, rehearsal Cluster/job/PVCs deleted, mClock back to `balanced`. osd.4 then took several minutes to restart (process D-state on its disk); until it did, 3 PGs were `down` because `min_size 1` had let single-copy writes land on it.
- Lesson: on this hardware the import's I/O is the same magnitude as the Ceph recovery it competes with; the Phase 4 gate (clean cluster) is a load requirement, not only a capacity one. Beta's OSD shares a device with etcd, so any OSD stall there is a control-plane stall.
- Rehearsal module disabled again (`_postgresql-rehearsal.nix`), commit pending in this session.

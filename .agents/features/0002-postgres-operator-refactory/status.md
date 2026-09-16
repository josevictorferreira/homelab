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

### 2026-09-16 09:48– BRT — Phase 5 cutover (user-approved: downtime OK, no data loss; software-only, no hardware changes)
Route changed from `bootstrap.initdb.import` to **workstation dump + rate-limited restore**:
- 09:48 production CNPG cluster `postgresql` applied (commit `5c8907d2`): empty initdb, LB 10.10.10.101, no backups/Database CRs yet (`_postgresql-backups.nix`). Healthy 09:58, single instance on lab-gamma-wk.
- osd.0 fell to 80 % once the reweight's remaps finished → replicapool MAX AVAIL 121 GiB.
- 09:33 watcher misfire (empty ceph response treated as "clean") had reverted `min_size`/`noout` and resumed Flux → 14 PGs peered; corrected 09:40, watcher patched and stopped for the window.
- 10:02 consumers scaled to 0 (`~/pg-migration/pg-consumers-scale.sh down`, replica counts in `replicas.txt`), plus open-webui/dramaturge/valoris/valoris-backend/hindsight-cp. Source `default_transaction_read_only = on`, CHECKPOINT. Ceph `nobackfill/norecover/norebalance`, mClock `high_client_ops`.
- 10:03 `final-dump.sh`: inventory → `pg_dumpall` → SHA256 (workstation NVMe). Then `final-restore.sh 10.10.10.101 15m` (pv-throttled psql), inventory + diff.
- Nix repoint done in working tree (20 files, `postgresql-18-hl` → `kubenix.lib.postgresHost`); commit only after the diff is clean. `postgresql-18` StatefulSet stays up read-only (Bitnami chart cannot scale the primary to 0); decommission in Phase 8.
- Rollback at any point before repoint: `pg-consumers-scale.sh up`, `ALTER SYSTEM RESET default_transaction_read_only`, unset Ceph flags.
- 10:20–13:31: restore ran in three legs. Leg 1 (workstation → LB, pv 15 MB/s) lost its TCP connection at 11:23 after I SIGSTOPped psql during an osd.1 spike; leg 2 (resume from the synapse block) lost it again at 12:15 with no server-side disconnect record — gamma's Cilium datapath flaps (the CNPG instance logged API-server unreachability at the same minutes). Leg 3 moved the whole thing **inside the pod**: dump + static `zstd` rsynced to gamma's host mount of the data PVC, restore over the Unix socket from line 14 821 179 (valoris_production onward).
- 13:31: leg 3 died: `client backend was terminated by signal 4: Illegal instruction`, kernel trap `in postgres[...]` on **lab-gamma-wk (Celeron N5105, no AVX)**. The Debian PG 18.6 build hit an instruction the N5105 lacks; `restart_after_crash=off` → clean shutdown → crash recovery. alpha is the same CPU. Fix: `affinity.nodeAffinity` pinning the cluster to lab-beta-cp/lab-delta-cp (commit `0aff394f`); pod recreated on delta 13:41, WAL redo in progress, then relaunch of the same in-pod slice (`relaunch-inpod.sh`).

### 2026-09-16 13:31–16:03 BRT — Phase 5 restore finished in-pod
- After the SIGILL on lab-gamma-wk the cluster got a hard node affinity to lab-beta-cp/lab-delta-cp (commit `0aff394f`, both have AVX2); the instance came back on delta. The remaining databases were restored from inside the pod over the Unix socket (`final-2026-09-16-1003.sql.zst` + a static musl `zstd` copied to the PVC), with `pg_terminate_backend` before each `DROP DATABASE` because app sessions from the failed legs were still attached.
- Verification (`scripts/pg-inventory-diff.sh`, strict mode): 79 databases, every ROLE/TABLE row count/SEQ/IDX/CONSTR identical to the frozen source; the only strict difference is the extra role `cnpg_metrics_exporter` that CNPG creates. Extension versions moved up as expected (vchord 0.5.3 → 1.1.1, vector 0.8.1 → 0.8.6). Files: `~/pg-migration/inv-final-{src,dst,diff}-2026-09-16-1003.txt`.
- Restore artifacts were deleted from the PVC afterwards (22 G used of 40 G).

### 2026-09-16 16:05–16:30 BRT — repoint applied
- Commit `6d5000e9` (rendered manifests for the 20 repointed files) pushed; Flux resumed; consumers scaled back up and rollout-restarted. Old `postgresql-18` stays up **read-only** (`default_transaction_read_only = on`) as the rollback until Phase 8.

### 2026-09-16 16:30–17:55 BRT — stragglers found by watching `pg_stat_activity` on both instances
- **grafana** kept the old host: the Helm chart Secret had the new `grafana.ini` but the pod could not be replaced — a surge pod needs 2 CPU of limits and the `monitoring` quota was at 8.9/10. Fixed by scaling the Deployment 0 → 1.
- **readeck** builds its DSN from the SOPS value `readeck_database_source`; the repoint could not reach it. Changed only the host inside that value with `sops --set` (credentials untouched, lock line + rendered file removed first), commit `ee048a8a`.
- **keycloak-0** was still running the previous StatefulSet revision (`--db-url` pointed at `postgresql-18-hl`), so pgjdbc rejected the read-only source with "Could not find a server with specified targetServerType: primary". Deleted the pod; the new revision starts in ~160 s.
- **mautrix-\*** (RWO PVCs, `RollingUpdate`): `kubectl rollout restart` creates a second ReplicaSet whose pod cannot attach the volume (Multi-Attach) while the old pod holds it, and Flux's next apply strips the `restartedAt` annotation, which flips the "current" ReplicaSet back and leaves both at 1 replica. Recovered with scale 0 → 1. Follow-up: `strategy: Recreate` for every RWO app.
- 10.0.1.28 on the old instance was my own psql through the LoadBalancer (Cilium SNAT), not a client.
- **`FATAL: sorry, too many clients already`** ~1 h after cutover: the ported parameter set had no `max_connections`, so CNPG's default 100 applied; every app connects as the superuser so the reserved slots were eaten too, and even the local socket (and therefore the operator's status probe) was refused. Freed slots by `kill -TERM` on idle backends via `/proc` (the image has no `ps`), then `max_connections = 300` + `tcp_keepalives_*` + `idle_session_timeout = 2h` in `_postgresql-lib.nix` (commit `421eb131`); the operator restarted the primary (3 min shutdown checkpoint on this storage). 62 connections in use afterwards.
- Old instance: 0 app clients since 17:20 BRT.

### 2026-09-16 17:00–17:55 BRT — Phase 6 enabled
- `postgresql-backups.nix` enabled + `plugins` stanza on the cluster (commits `cf5201ad`, `9b9f2dd6`, `421eb131`, `6a738c12`). Two fixes were needed against the disabled draft: `data.compression` must be one of bzip2/gzip/lz4/snappy in plugin-barman-cloud 0.8 (zstd is WAL-only → gzip), and the Database CR field is `spec.name`, not `spec.db`.
- Result: `ContinuousArchiving=True`, `pg_stat_archiver` 1047 archived / 21 failed (the failures are the restart window), WAL objects visible in `s3://homelab-backup-postgres/cnpg/postgresql/wals/` on the Pi; 32/32 Database CRs `applied=true`; ObjectStore `pi-minio` and ScheduledBackup `postgresql-daily` exist.
- Deviations: `immediate = false` and the schedule moved to 04:00 UTC (01:00 local) so the ~22 GB base backup never overlaps the 02:30 local logical dump; the **first base backup is still to be taken by hand** once Ceph recovery is done (a manual `Backup` CR or wait for 01:00).
- `postgres-restore-drill` disabled (`_postgres-restore-drill.nix`): it has failed weekly since 2026-08-30 and cannot fit a 22 GB restore in an 8Gi emptyDir, a node's disk, or an affordable RBD volume at today's MAX AVAIL. Re-enable conditions are in the file header. The logical `postgres-backup` CronJob works against the new host (job completed 16:5x BRT).
- Not done from Phase 6: alert rules for failed/missing backups (6.3), the PITR drill (also needs a scratch PVC), CLAUDE.md note added below.

### Incidents during the fix-up
- **lab-gamma-wk hard resets** at 16:41, 16:47, 16:53 and 16:58 BRT (uptimes 344 s, 337 s, 203 s, 348 s), journal ends mid-line, no `Power key`, package temp 72–78 °C under the 4 W cap → not the known thermal or ACPI causes. Each reset flapped osd.3/osd.5, stalled RBD, and twice took the API server down (`TLS handshake timeout`, delta briefly NotReady). Mitigation without hardware changes: cordon, delete the two OSD pods, scale `rook-ceph-osd-3/5` to 0 (Rook leaves the replica count alone); gamma has been up since 16:59 with no OSDs, uncordoned at 17:14 because alpha/beta/delta had no CPU requests left for keycloak/immich/hindsight. `osd.3` (SSD) scaled back to 1 at 17:43 as a controlled test; `osd.5` (HDD, spin-up load) still at 0. The tighter cap is now durable in Nix (`intel-nuc-gk3v.nix`: gamma 4 W/6 W/1.2 GHz, alpha unchanged) and deployed to gamma with the copy+switch recipe.
- **etcd**: leader was lab-beta-cp whose ZFS root was 82 % full / 62 % fragmented with the NVMe saturated (shared with osd.4); ~1000 "apply request took too long" per 3 min on every member, k3s on beta restarted itself at 17:22. Moved leadership to lab-delta-cp with `etcdctl move-leader` (k3s's etcd has no gRPC gateway; certs copied from `/var/lib/rancher/k3s/server/tls/etcd/`), and `k3s crictl rmi --prune` on beta freed 11.7 GB (109 → 27 images, rpool/root 36.1 → 24.4 G).

### State at 17:55 BRT
- CNPG `postgresql`: healthy, 2/2 (postgres + barman sidecar), 79 DBs, all consumers connected, WAL archiving on. Old `postgresql-18-0`: Running read-only on gamma, 0 clients (rollback until Phase 8, ≥ 14-day soak per plan).
- Ceph: 5/6 OSDs up, 17 % degraded, `min_size 1` + `noout` still set, `ceph-restore-replication.sh` watcher running (restores `min_size 2`/unsets `noout` when clean — it cannot become clean while osd.5 is down).
- Pods: everything Running except `wealtho` (CrashLoopBackOff in `db:prepare`, see below).

### 2026-09-16 18:10 BRT — end of session state
- `osd.3` back at 17:43 and `osd.5` at 17:59 (one at a time, after gamma had run 60 min without OSDs); gamma still up at 18:10 (68 min, load 16 from recovery, 72 °C, 4 W cap). All 6 OSDs up, 1.3 % degraded / 2.5 % misplaced and falling; `min_size 1` + `noout` remain until the watcher sees a clean cluster.
- `wealtho` was not a database problem: on the 1.2 GHz node Puma needs > 60 s to bind and the 30 s + 3×10 s liveness budget killed it in a loop. Probes relaxed (commit `29668a59`); Running.
- etcd leader moved to lab-delta-cp; beta's root freed by 11.7 GB (`crictl rmi --prune`).
- Cluster: zero unhealthy pods, Flux Ready at `29668a59`, CNPG healthy with archiving, 68 connections / 17 databases / 15 clients on the new cluster, 0 clients on the read-only old instance.
- Still open: first CNPG base backup (manual `Backup` or the 01:00 local schedule), backup alerting (6.3), PITR drill, Phase 7 soak → Phase 8 decommission of `postgresql-18` (user decision), `strategy: Recreate` for RWO apps, revert `ceph osd reweight osd.0 0.85` → 1.0 after the balancer settles, and the gamma reset cause (power/board, not thermal) which no software setting fixes.

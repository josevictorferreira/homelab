# Draft: Homelab backup strategy (Rook/Ceph + Postgres → Pi)

## Requirements (confirmed)
- Need **automatic periodic backups** for:
  - CephFS **subvolume folders only** (partial paths)
  - Rook Ceph **RBD / block PVCs**
  - Rook Ceph **Object Store buckets**
  - In-cluster **PostgreSQL** databases
- Backup target: **Raspberry Pi (NixOS, not in k8s)** with **external 1TB drive**.
- Resiliency goal: backups **outside** k8s; avoid competing with workloads.
- Desire: **UI** to browse backups + **easy restore**, plus **alerts**; Grafana integration is a plus.
- Current state: some **CephFS snapshots** already configured.
- Pain point: CephFS subvolume deleted → data loss; wants strong recoverability even if rook disks/volumes fail.
- OK with running tooling **inside k8s or outside**; if outside must be managed via **Nix**.
- Pi already runs **MinIO** on the external drive (potential S3 target).
- RPO: **24h acceptable**.
- CephFS selection: **subpaths inside mounted CephFS PVC**.
- CephFS layout change: OK to **split critical folders into separate PVC/subvolumes**.
- Postgres: **Bitnami legacy chart**; preference: **periodic full dumps**.
- UI: **nice-to-have**, correctness/automation first.
- Retention (initial): **14 daily**.
- Budget: **OSS-only**.
- Encryption: prefer **easiest/lowest-complexity**.
- Data sizes (rough):
  - CephFS total: **2.4TB** (but only subset is in-scope for offsite)
  - Largest PVC: **60GiB** (ollama models; low priority)
  - Postgres: **2.5GiB now**, could grow to **~15GiB**
- Pi MinIO: currently **no TLS**.
- MinIO transport choice: **LAN HTTP only**.
  - Risk accepted; prefer minimal services/config.
- Tier-1 restore target(s): **Postgres only**.
- Also backup **Kubernetes objects** (namespaces/CRDs/secrets): **YES**.
- Critical CephFS subset to offsite: **<100GiB**.
- RGW buckets to protect: **<100GiB**.
- Velero k8s objects: **YES**, but **exclude Secrets** (rely on GitOps + SOPS).
- Schedules: **daily (nightly)** for Postgres dumps + general PVC backups.
- Alerts routing: **Grafana only** (dashboards/alerts; no paging targets).
- Postgres dumps: **plaintext OK** (access control only; no extra encryption).
- Also copy **k3s/etcd snapshots** off-cluster to Pi: **YES**.
- 2nd copy / offsite: **later** (single-target acceptable for baseline).
- Restore drill cadence (tier-1 Postgres): **weekly** (restore into scratch + basic query checks).

## Scope boundaries (initial)
- INCLUDE: backup architecture + tool shortlist, pro/cons, recommended approach, and an implementation work plan (GitOps + Nix).
- EXCLUDE (for now): changing Ceph/Rook topology, resizing cluster storage, or any destructive Ceph operations.

## Technical decisions (pending)
- Primary backup platform: (TBD)
- Backup target format: object storage (MinIO S3) vs filesystem repo on Pi (borg/restic) vs both.
- Encryption: at-rest + in-transit (TBD)
- Retention + prune policy (TBD)
- Restore workflow: self-serve UI vs CLI + runbooks (TBD)

## Research findings (pending)
- (pending) Existing repo patterns for apps/modules and any current backup tooling
- (pending) Best-in-class tools for CephFS/RBD/RGW + Postgres backups; UI/alerts/Grafana options

## Research findings (Oracle)
- Arch: **Pi MinIO as off-cluster backup hub**; versioning + lifecycle + per-writer creds.
- k8s objects + PVC data: **Velero + Kopia** to MinIO.
- RGW buckets: **rclone S3→S3 mirror** (RGW → MinIO).
- Guidance: keep Ceph snapshots for short-term rollback only; add **restore drills** + alert on them.

## Open questions
- Approx **data sizes** + growth for: CephFS datasets, RBD PVCs, RGW buckets, Postgres?
- Network: Pi reachable from cluster nodes on LAN? Any firewall/VLAN/TLS constraints?
- Do you also want **Kubernetes object backups** (namespaces/CRDs/secrets) as part of the solution? (Velero does this.)
- Any “tier-1” apps that must have restore drills (e.g., Postgres + Immich)?
- How much **CephFS subset** is actually “critical” (GiB/TiB) to fit 1TB target incl retention?
- MinIO endpoint hardening: add **TLS** (how) vs accept LAN HTTP + rely on client-side encryption?

---

## 7. Recommended Backup Strategy & Implementation Plan

This plan follows a **Hybrid Architecture**: In-cluster agents perform the data extraction (for native access to PVCs and Services) while targeting an **Off-cluster hub** (Raspberry Pi) for fault isolation and storage.

### 7.1 Component List & Placement

| Component | Tooling | Runtime Location | Storage Target |
| :--- | :--- | :--- | :--- |
| **Backup Hub** | MinIO (NixOS) | Raspberry Pi | External 1TB HDD |
| **k8s Objects** | Velero | In-Cluster | Pi MinIO (S3) |
| **PVC Data (RBD/FS)** | Velero + Kopia | In-Cluster | Pi MinIO (S3) |
| **RGW Buckets** | rclone | In-Cluster (CronJob) | Pi MinIO (S3) |
| **Postgres Dumps** | pg_dumpall (Bitnami) | In-Cluster (CronJob) | Pi MinIO (S3) |
| **etcd Snapshots** | k3s native + upload | In-Cluster (CronJob) | Pi MinIO (S3) |

### 7.2 Pro/Cons: In-Cluster vs On-Pi Placement

| Feature | In-Cluster Tooling (Targeting Pi) | On-Pi Tooling (Fetching) |
| :--- | :--- | :--- |
| **Access** | **PRO**: Direct access to PVs/Pods | **CON**: Needs NodePort/Auth exposure |
| **Isolation** | **CON**: Tooling depends on cluster health | **PRO**: Independent logic (Safe) |
| **Complexity** | **PRO**: Standard Helm/Kubenix modules | **CON**: Custom Nix/Systemd scripts |
| **Performance** | **PRO**: Efficient IO directly from node | **CON**: Network bottlenecked |
| **Recommendation** | **Hybrid** (In-cluster tools + Pi storage) | |

### 7.3 Implementation Work Plan (Phased)

#### Phase 1: Foundation (The Backup Hub)
- [ ] **Pi MinIO Configuration**: Define NixOS module for MinIO on the Pi.
  - Mount external HDD to `/mnt/backups`.
  - Service: `services.minio.enable = true` (HTTP only, per preference).
- [ ] **Identity & Access**:
  - Create buckets: `velero`, `postgres`, `rgw`, `etcd`.
  - Generate per-service S3 credentials with restricted policies (least-privilege).

#### Phase 2: Tier-1 Resilience (Postgres)
- [ ] **Backup Job**: Implement a Kubenix `CronJob` using the `bitnami/postgresql` image.
  - Logic: `pg_dumpall | mc pipe s3-pi/postgres/full-$(date +%F).sql`.
  - Schedule: Daily at 02:00 AM.
- [ ] **Restore Script**: Update the `Makefile` with `make restore_drill_postgres` to automate weekly verification into a scratch namespace.

#### Phase 3: Filesystem & K8s Objects (Velero)
- [ ] **Installation**: Deploy Velero via Kubenix.
  - Plugin: AWS (for S3 compatibility).
  - Uploader: **Kopia** (native filesystem backups for CephFS/RBD).
- [ ] **Configuration**:
  - Filter: Exclude `v1/Secrets` globally.
  - Metadata: Annotate pods for critical CephFS subpaths (<100GiB) and RBD volumes.
- [ ] **Schedule**: Daily at 03:00 AM.

#### Phase 4: Storage Mirror & System State
- [ ] **RGW Mirror**: Deploy an `rclone sync` CronJob to mirror production RGW buckets to the Pi.
- [ ] **etcd Offloading**: Deploy a CronJob to copy k3s local etcd snapshots (`/var/lib/rancher/k3s/server/db/snapshots/`) to the Pi via S3 upload.

#### Phase 5: Hardening & Observability
- [ ] **Grafana Integration**: Import Velero and MinIO dashboards.
- [ ] **Alerting**: Set up PromQL alerts for:
  - `minio_disk_utilization > 85%`
  - `velero_backup_failure_total > 0`
  - `time() - last_successful_postgres_dump > 93600` (26 hours).

### 7.4 Key Decisions Record
- **Retention**: 14 daily snapshots (managed by MinIO Lifecycle Policies).
- **Encryption**: Kopia-native encryption for PVCs; Postgres dumps are plaintext (restricted by S3 IAM).
- **Secrets**: Excluded from backups (GitOps/SOPS is the source of truth).
- **Restore Cadence**: Weekly manual/automated drill for Postgres.

### 7.5 Risks & Mitigations
- **Network Bottleneck**: Staggered schedule (Postgres 02:00, Velero 03:00, RGW 04:00) to prevent saturating Pi 1Gbps link.
- **Data Corruption**: Mitigated by weekly restore drills on the most critical dataset (Postgres).
- **Credential Security**: Credentials stored in SOPS-encrypted K8s Secrets and injected via `vals` during manifest generation.

### 7.6 Effort Estimate
- **Prep & Pi Hub**: 4h
- **Postgres Tier-1**: 3h
- **Velero/Kopia**: 5h
- **RGW/etcd/Alerts**: 3h
- **Total**: ~15h engineering time.

### 7.7 Tool Selection Summary

| Data Class | Tool | Why |
| :--- | :--- | :--- |
| **k8s Objects** | Velero | Native K8s integration, CRD-based backup/restore, excludes Secrets |
| **PVC Data (RBD/CephFS)** | Velero + Kopia | File-level backups independent of Ceph survival; Kopia for efficiency |
| **RGW Buckets** | rclone | Simple S3→S3 mirror with versioning at destination |
| **Postgres** | pg_dumpall + mc | Simplest for Bitnami chart; meets 24h RPO |
| **etcd Snapshots** | k3s native + CronJob | Standard k3s snapshots, copied off-cluster |
| **Inventory UI** | Grafana + Headlamp | Grafana for metrics/alerts; Headlamp for browsing Velero CRs |

### 7.8 Alternative Tools Considered (and rejected)

| Tool | Why Not Chosen |
| :--- | :--- |
| **Kasten K10** | Commercial; OSS-only constraint |
| **TrilioVault** | Commercial; OSS-only constraint |
| **Longhorn** | Would require storage migration; not needed |
| **Stash (AppsCode)** | Paid features for advanced functionality |
| **Restic (standalone)** | Kopia preferred for Velero integration |

### 7.9 Success Criteria

- [ ] Daily Postgres dumps to MinIO with <1% failure rate
- [ ] Weekly restore drill passes (restore to scratch + query check)
- [ ] Velero backups complete nightly for annotated PVCs
- [ ] RGW bucket mirror completes with object count verification
- [ ] Grafana alerts fire on backup failures and disk utilization
- [ ] etcd snapshots copied off-cluster within 24h of creation
- [ ] Restore runbooks documented and tested

### 7.10 Rollback Plan

If any component fails catastrophically:
1. **Postgres**: Restore from latest dump to new instance; update app connection strings
2. **PVC Data**: Restore from Velero backup to new PVC; remount to application
3. **RGW**: Sync back from MinIO mirror to new RGW bucket
4. **etcd**: Restore from off-cluster snapshot using k3s standard procedure
5. **Full cluster loss**: Rebuild from GitOps + restore data from MinIO backups

### 7.11 Future Enhancements (Phase 6+)

- [ ] Add TLS to MinIO endpoint
- [ ] Implement second copy target (another USB drive or cloud)
- [ ] Add client-side encryption for Postgres dumps
- [ ] Expand restore drills to include CephFS/RBD PVCs
- [ ] Implement automated backup verification (checksums, test restores)
- [ ] Add backup size trending and capacity planning alerts

# Research: Kubernetes-native PostgreSQL (operator) for the homelab

**Date:** 2026-09-15
**Status:** research complete, no changes made to repo or cluster
**Decision:** adopt **CloudNativePG (CNPG)**; migrate by logical import, side by side, old volume retained

---

## 1. Current state (measured on the live cluster)

| Item | Value |
|---|---|
| Deployment | Bitnami `postgresql` Helm chart 16.7.27 via kubenix, single StatefulSet `postgresql-18` in `apps` |
| Image | `ghcr.io/josevictorferreira/postgresql-vchord-bitnami:38c40fef…` — hand-maintained Dockerfile (Bitnami minideb + binaries copied from `ghcr.io/immich-app/postgres:18-vectorchord0.5.3-pgvector0.8.1`), separate GitHub repo, last push 2025-12-25 |
| PostgreSQL | 18.1, `data_checksums=on`, `wal_level=replica` |
| Databases | 81 total, 23 GB. Largest: valoris_production 14 GB, synapse 3.8 GB, hindsight 1.6 GB, valoris_production_queue 873 MB, n8n 753 MB |
| Roles | `postgres` (superuser, used by **every** app), `immich` (login, non-super) |
| Extensions in use | `vchord` 0.5.3 + `vector` 0.8.x in almost every DB; `postgis` in valoris_*; `uuid-ossp`, `unaccent`, `pg_trgm`, `cube`, `earthdistance`, `pgcrypto` scattered (all contrib) |
| Provisioning | Bootstrap Job loops `CREATE DATABASE` + `CREATE EXTENSION vchord` over `homelab.kubernetes.databases.postgres` (config/kubernetes.nix) |
| Consumers | 22 kubenix files reference `postgresql-18` / `postgresql-18-hl`; all connect as `postgres` with `postgresql_admin_password` |
| Service | `postgresql-18` is a LoadBalancer on 10.10.10.133 (`plainServiceFor`), `postgresql-18-hl` headless is what apps use |
| Storage | PVC `data-postgresql-18-0` 40Gi on `rook-ceph-block` (pool `replicapool`, nvme, size 3), PV reclaim **Retain**, 25G used, one 8 GiB RBD snapshot from 2026-01-29 still attached |
| Backups | CronJob `postgres-backup` (02:30 BRT): `pg_dumpall \| zstd` → Pi MinIO `homelab-backup-postgres`; weekly `postgres-restore-drill` restores latest dump into a scratch Bitnami pod |
| Kubernetes | k3s v1.32.7, containerd 2.0.5; cert-manager present; no VolumeSnapshotClass |
| Quotas | `apps`: limits.memory **46.3Gi / 48Gi used**, LimitRange max 4Gi/container. `backup`: 2 CPU / 4Gi |

### Red flags found during research (pre-existing, unrelated to this feature)

1. **Postgres backups are failing.** `postgres-backup` jobs on 2026-09-13/14/15 all `BackoffLimitExceeded`; `postgres-restore-drill` failing since 2026-08-30 (`DeadlineExceeded`). Last successful dump: **2026-09-07**.
2. **Pi MinIO is down.** `lab-pi-bk`: `zpool-import-backup` = failed, `minio` = inactive, `/mnt/backups` not mounted, port 9000 closed. See memory `pi-backup-pool-incident-2026-08`.
3. **Ceph is nearly full.** `replicapool` 97.7% used, **MAX AVAIL 6 GiB**; osd.0 (delta, nvme) 94%, osd.5 (gamma, hdd) 90%; `HEALTH_WARN`: 1 backfillfull, 2 nearfull, 72 PGs backfill_toofull, 42 PGs degraded. **A new 40Gi PVC cannot be provisioned safely today.**

All three are hard prerequisites for the plan (see plan.md Phase 0).

---

## 2. Why move off the current setup

- Bitnami moved free versioned images to the frozen `bitnamilegacy` namespace (Aug/Sep 2025); the current image is a fork of a Bitnami Dockerfile that only we maintain.
- Databases/extensions are created imperatively by a Job; per-app extension needs (postgis, pg_trgm…) are not declared anywhere.
- No WAL archiving / PITR; a nightly `pg_dumpall` is the only recovery point (and it is currently broken).
- Probe/termination tuning had to be hand-derived after a power-outage recovery deadlock (memory `postgres-recovery-liveness-deadlock`); an operator owns this.

---

## 3. Operator landscape, September 2026

| Operator | Latest | Health / community | Extensions | Verdict for this cluster |
|---|---|---|---|---|
| **CloudNativePG** | 1.30.0 (2026-06-29), minor every 3 months, PG 14–18, K8s 1.34–1.36 | CNCF Sandbox (incubation applied 2025-11, open), ~9.3k stars, IBM/Google/Azure/Tesla adopters, ≈173 home-ops repos on kubesearch.dev | Official `minimal`/`standard` images (standard has pgvector), official PostGIS image, OCI extension images via ImageVolume on PG18 | **Chosen** |
| Zalando postgres-operator | 2.0.2 (2026-08-20), ~1 minor/year | alive but slow; PG18 took 10 months to release; Spilo-bound | only what Spilo ships → custom Spilo for vchord | rejected: same custom-image burden as today, weaker cadence |
| Crunchy PGO | 6.0.x (2026-06) | active, technically strong | pgvector + PostGIS in Crunchy images | rejected: images gated by Developer Program terms, old tags removed, no redistribution |
| StackGres | 1.19.0 (2026-07-22) | very active, AGPLv3 | 223-entry catalog incl. `vchord`, `vector`, `postgis` installed on the fly | runner-up: richest extension story, but AGPL, small community, Patroni stack |
| Percona for PostgreSQL | 3.1.0 (2026-09-09), PGO fork | corporate cadence, ~385 stars | pgvector + PostGIS | rejected: small community, no vchord |
| Kubegres | 1.19 (2025-01) | dormant | none | rejected |

Community consensus in 2026 comparisons: "for a new deployment with no Patroni investment, CloudNativePG is the default". Homelab migrations off Bitnami and off Zalando both land on CNPG; Immich/VectorChord users cite it explicitly.

---

## 4. CloudNativePG facts that shape the plan

### Releases and charts
- Operator 1.30.x (default PG image 18.4); Helm charts: `cloudnative-pg-v0.29.0`, `cluster-v0.8.1`, `plugin-barman-cloud-v0.8.0` (repo `https://cloudnative-pg.github.io/charts`).
- `kubectl cnpg` plugin: `status`, `promote`, `restart`, `reload`, `backup`, `psql`, `logs`, `hibernate`, `report`.

### Backups
- In-tree `spec.backup.barmanObjectStore` is **deprecated (removed in 1.31)**. Use **plugin-barman-cloud** (v0.15.0, needs cert-manager, one sidecar per PG pod): `ObjectStore` CR (S3-compatible: MinIO / Ceph RGW; `endpointURL`, `s3Credentials`, `retentionPolicy` lives here) + `spec.plugins[{name: barman-cloud.cloudnative-pg.io, isWALArchiver: true}]` on the Cluster + `ScheduledBackup` (`method: plugin`, six-field cron).
- Continuous WAL archiving gives PITR; recovery = new Cluster with `bootstrap.recovery` + `externalClusters[].plugin`.
- Volume-snapshot backups exist but need a VolumeSnapshotClass (none here) and still need WAL archive for PITR.

### Extensions and images
- Image catalog `ghcr.io/cloudnative-pg/postgresql:18-{minimal,standard,system}-{bookworm,trixie}` (verified: `18-standard-trixie`, `18.6-standard-trixie` exist). `ghcr.io/cloudnative-pg/postgis:18-3.6-{standard,system}-trixie` exists.
- **ImageVolume extensions** (`spec.postgresql.extensions`) need PG18 **and K8s 1.35+** (1.33/1.34 with `ImageVolume` gate) **and containerd ≥ 2.1**. Cluster is k3s 1.32.7 / containerd 2.0.5 → **not available until k3s is upgraded**. Any extension change restarts pods.
- **VectorChord:** `ghcr.io/tensorchord/cloudnative-vectorchord:18.6-1.1.1` exists (verified on GHCR: linux/amd64+arm64, digest `sha256:c7672bc0…`). Built from `postgres:18-bookworm` (contrib included) + pigsty: pgvector, vchord 1.1.1, vchord_bm25, pg_tokenizer, pgaudit, pg_failover_slots, uuid-ossp, pg_stat_statements; runs as uid 26; barman-cloud installed. **No PostGIS.**
- ⇒ No upstream image has both vchord and postgis. A **custom image is still required**, but it shrinks to `FROM cloudnative-vectorchord` + `apt-get install postgresql-18-postgis-3`.
- `shared_preload_libraries` must include `vchord.so` (Immich hard requirement; also used by every other DB here).

### Declarative databases and roles
- `Database` CR: `name`, `owner`, `cluster.name`, `ensure`, `databaseReclaimPolicy` (`retain`/`delete`), `extensions[{name, version, ensure}]`, `schemas[]`. Primary-only, no rename, not for `postgres`/`template*`.
- `managed.roles[]` (`login`, `superuser`, `inRoles`, `passwordSecret` → `kubernetes.io/basic-auth` Secret) and new `DatabaseRole` CR (1.30).
- `enableSuperuserAccess: true` + `superuserSecret` keeps the `postgres` superuser usable with a password we control → apps need only a hostname change.

### Import / bootstrap
- `bootstrap.initdb.import` **monolith mode** (`databases: ["*"]`, `roles: ["*"]`): pg_dump/pg_restore from `externalClusters[]` over the network, offline, strips SUPERUSER from imported roles (postgres role itself is never imported), `postImportApplicationSQL`, `pgDumpExtraOptions`/`pgRestoreExtraOptions`. Source only needs a superuser connection; source image does **not** need to be CNPG-compatible.
- `bootstrap.pg_basebackup` (physical) is same-major only and would carry Bitnami's on-disk quirks and vchord 0.5.3 libraries into the new cluster → rejected; logical import gives a clean initdb, fresh checksums, vchord 1.1.1 and rebuilt indexes.
- Declarative major upgrades (`pg_upgrade --link`) since 1.26.

### Services / footprint
- Services `<cluster>-rw`, `-ro`, `-r`; extra services (e.g. LoadBalancer for 10.10.10.133) via `managed.services.additional`.
- `instances: 1` is supported; a replica later is one field (+ another PVC). One RWO PVC per instance, optional separate `walStorage` (recommended: WAL filling PGDATA is a known pain point). RBD is fine.
- Parameters CNPG owns and rejects in `postgresql.parameters`: `listen_addresses`, `port`, `wal_level`, `hot_standby`, `archive_*`, `logging_collector`, `log_destination`, `ssl*`, `wal_log_hints`, `cluster_name`… (drop these from the current `extendedConfiguration` when porting).

### Known pain points (2025–2026)
- Barman plugin migration friction (rolling restarts, renamed metrics, docs lag) → start directly on the plugin.
- Every extension/ImageVolume change restarts pods; weekly moving tags → pin digests.
- Restart-requiring GUC changes can trigger a double switchover with >1 instance.
- No backups by default; PgBouncer defaults low.

---

## 5. Constraints specific to this homelab (drive the plan)

1. **Backups broken + Pi MinIO down** → must be fixed and a fresh verified dump taken *before* anything else.
2. **Ceph capacity** → need ≥ ~60 GiB free in `replicapool` (48Gi new PVCs + import scratch + RBD snapshot COW) before provisioning. This is the user's decision (what to delete / add).
3. **Custom image** (vchord + postgis) → new small Dockerfile on top of `cloudnative-vectorchord`, digest-pinned, private GHCR → `ghcr-registry-secret` in new namespace.
4. **k3s 1.32** → ImageVolume extensions out of scope; revisit after a k3s upgrade.
5. **`apps` quota full** → new namespace `databases` with its own ResourceQuota/LimitRange (bootstrap/resource-quotas.nix, namespaces.nix are generated from `homelab.kubernetes.namespaces`).
6. **22 files hardcode `postgresql-18-hl`** → introduce one `_lib` helper for the DB host and update all call sites in one commit; also `postgresql-auth.enc.nix` Grafana datasources, `backup/postgres-backup.nix`, `backup/postgres-restore-drill.nix`, `tuwunel-media-retention.nix`.
7. **NetworkPolicy `postgresql-18`** exists in `apps` → import from the `databases` namespace must be allowed (verify before cutover).
8. **All apps use the `postgres` superuser** → keep superuser access enabled on CNPG with the same password (`postgresql_admin_password`) so cutover is hostname-only; per-app roles are a separate, later feature.
9. **LoadBalancer IP 10.10.10.133** → recreate via `managed.services.additional` + cilium `lbipam` annotations (external tools / Grafana / host access).

---

## 6. Sources

- CNPG: [releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) · [supported releases](https://cloudnative-pg.io/docs/1.30/supported_releases/) · [v1.30 notes](https://cloudnative-pg.io/docs/1.30/release_notes/v1.30/) · [backup](https://cloudnative-pg.io/docs/1.30/backup/) · [plugin-barman-cloud](https://github.com/cloudnative-pg/plugin-barman-cloud) · [plugin usage](https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/) · [recovery](https://cloudnative-pg.io/docs/devel/recovery/) · [ImageVolume extensions](https://cloudnative-pg.io/docs/1.30/imagevolume_extensions/) · [postgres-containers](https://github.com/cloudnative-pg/postgres-containers) · [postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers) · [declarative databases](https://cloudnative-pg.io/docs/1.30/declarative_database_management/) · [roles](https://cloudnative-pg.io/docs/1.30/declarative_role_management/) · [import](https://cloudnative-pg.io/docs/1.30/database_import/) · [bootstrap](https://cloudnative-pg.io/docs/1.30/bootstrap/) · [major upgrades](https://cloudnative-pg.io/docs/1.30/postgres_upgrades/) · [services](https://cloudnative-pg.io/docs/1.30/service_management/) · [pooling](https://cloudnative-pg.io/docs/1.30/connection_pooling/) · [resources](https://cloudnative-pg.io/docs/1.30/resource_management/) · [storage](https://cloudnative-pg.io/docs/1.30/storage/) · [charts](https://github.com/cloudnative-pg/charts) · [kubectl plugin](https://cloudnative-pg.io/docs/1.30/kubectl-plugin/)
- VectorChord: [VectorChord-images (vchord-cnpg Dockerfile)](https://github.com/tensorchord/VectorChord-images) · GHCR `ghcr.io/tensorchord/cloudnative-vectorchord` tags verified 2026-09-15
- Immich: [pre-existing Postgres](https://docs.immich.app/administration/postgres-standalone/)
- Others: [Zalando releases](https://github.com/zalando/postgres-operator/releases) · [Zalando user docs](https://github.com/zalando/postgres-operator/blob/master/docs/user.md) · [Crunchy 6.0.x notes](https://access.crunchydata.com/documentation/postgres-operator/latest/releases/6.0.x) · [Crunchy terms](https://www.crunchydata.com/developers/terms-of-use) · [StackGres changelog](https://github.com/ongres/stackgres/blob/main/CHANGELOG.md) · [StackGres extension index](https://extensions.stackgres.io/postgres/repository/v2/index.json) · [Percona releases](https://github.com/percona/percona-postgresql-operator/releases) · [Kubegres](https://github.com/reactive-tech/kubegres)
- Context: [Bitnami image change](https://github.com/bitnami/charts/issues/35164) · [CNPG vs PGO (Bartolini)](https://www.gabrielebartolini.it/articles/2026/05/cloudnativepg-and-crunchy-pgo-an-honest-opinionated-comparison/) · [CNPG in 2025 (Bartolini)](https://www.gabrielebartolini.it/articles/2025/12/cloudnativepg-in-2025-cncf-sandbox-postgresql-18-and-a-new-era-for-extensions/) · [Zalando→CNPG migration](https://shawnwilsher.com/2026/01/migrating-from-zalados-postgres-operator-to-cloudnativepg/) · [Bitnami→CNPG migration](https://jasongodson.com/blog/cloudnative-pg-migration/) · [kubesearch CNPG](https://kubesearch.dev/hr/ghcr.io-cloudnative-pg-charts-cloudnative-pg) · [operators compared 2026](https://chat2db.ai/resources/blog/postgres-kubernetes-operators-compared) · [PG18 + ImageVolume + CNPG](https://bex.co/blog/2026/07/31/postgres-18-kubernetes-imagevolume-cnpg-extensions)

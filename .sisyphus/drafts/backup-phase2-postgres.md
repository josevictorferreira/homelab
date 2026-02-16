# Draft: Phase 2 Tier-1 Resilience (Postgres)

## Source
- Derived from: `.sisyphus/drafts/backup-strategy.md` (Phase 2 section only)

## Objective
- Plan + implementable task breakdown for **Tier-1 Postgres resilience**:
  - Daily full logical dumps (RPO 24h)
  - Stored **off-cluster** on Pi MinIO (S3)
  - Weekly restore drill into scratch + basic query checks

## Confirmed constraints (from source draft)
- Postgres runs in-cluster; **Bitnami legacy chart**
- Backups: **periodic full dumps** preferred
- Target: **Pi MinIO** on external 1TB (HTTP LAN OK)
- Retention: **14 daily** (initial)
- Encryption: **plaintext OK** for Postgres dumps (access control only)
- Alerts: Grafana only (nice-to-have)
- Restore drill cadence: weekly

## Open items / assumptions (to validate via repo search)
- Where Postgres is defined (module path), namespace, Service name
- Auth source for dump job (DB user/secret key names)
- Existing S3/MinIO secret patterns (kubenix secretsFor / enc.nix naming)
- Existing CronJob conventions (resources, serviceAccount, tolerations, etc.)
- Existing Makefile patterns for restore scripts / kubectl helpers

## Repo findings (confirmed)
- Postgres module: `modules/kubenix/apps/postgresql-18.nix`
  - Namespace: `apps`
  - Release: `postgresql-18`
  - Service hostname used by apps: `postgresql-18-hl:5432`
- Auth secret: `postgresql-auth` (from `modules/kubenix/apps/postgresql-auth.enc.nix`)
  - Key used in bootstrap job: `admin-password`
- DB list source: `config/kubernetes.nix` → `homelab.kubernetes.databases.postgres`
  - Current DBs: linkwarden, openwebui, n8n, immich, valoris_production, valoris_production_queue, keycloak, synapse, mautrix_slack, mautrix_discord, mautrix_whatsapp
- Existing ops commands:
  - `make backup-postgres` / `make restore-postgres` exist
  - Implementation in `modules/commands.nix` currently writes `/tmp/backup/full_backup.sql` to local + uses fixed IPs (not MinIO)
- MinIO Phase 1 plan exists: `.sisyphus/plans/backup-hub-identity-access.md`
  - Bucket name in plan: `homelab-backup-postgres`

## Proposed Phase-2 design (draft)
- Daily K8s CronJob (in `modules/kubenix/apps/`):
  - Run `pg_dumpall` (or per-db dumps) against `postgresql-18-hl`
  - Stream/compress → upload to Pi MinIO S3 bucket
  - Retain 14 daily via MinIO ILM
- Weekly restore drill:
  - Fetch latest dump from MinIO
  - Restore into scratch Postgres in scratch namespace OR restore into temp DBs on same cluster (prefer scratch instance)
  - Run validation queries (smoke + row counts + schema present)
  - Capture evidence + fail job if any check fails

## Open decisions (need user)
- Dump format: `pg_dumpall` (global) vs per-DB `pg_dump` (more granular)
- Compression: none vs gzip vs zstd
- Schedule window (daily time) + weekly drill time
- Restore drill target: scratch Postgres instance vs restore into existing cluster (riskier)
- Validation depth: minimal smoke vs deeper checks (tables, counts, extensions)
- Alerting: CronJob fail only vs also “backup freshness” metric/alert

## Decisions (confirmed by user)
- Dump: `pg_dumpall`
- Restore drill: scratch Postgres instance (in-pod/namespace isolated)
- Compression: zstd
- Validation: smoke
- Alerting: CronJob failure only
- Schedule: daily 02:30 + weekly Sun 03:00, local timezone

## Still unclear / need confirmation
- How should we package tools for backup/drill jobs?
  - Need: `pg_dumpall` + `psql` + `zstd` + S3 uploader (`mc` or `rclone`) + TLS CA certs
  - Option A: custom “backup-toolbox” OCI image pinned by digest (most reliable)
  - Option B: use existing images + add tools at runtime (fragile)
- Where should MinIO S3 creds for in-cluster jobs live?
  - Likely `secrets/k8s-secrets.enc.yaml` + kubenix `*.enc.nix` Secret using `kubenix.lib.secretsFor`
- Confirm MinIO endpoint + bucket naming/path convention for objects

## Decisions (confirmed by user, round 2)
- Job tooling: custom pinned “backup toolbox” OCI image
- S3 uploader: `mc`
- MinIO endpoint: `http://10.10.10.209:9000`
- Bucket: `homelab-backup-postgres`
- Object key convention (proposed): `postgresql-18/YYYY/MM/DD/full.sql.zst` + `full.sql.zst.sha256`
- S3 creds source: `secrets/k8s-secrets.enc.yaml` + kubenix Secret via `kubenix.lib.secretsFor` (job uses `secretKeyRef`)
- CronJob TZ: `America/Sao_Paulo`

## Blocking decision (need user)
- Where should the custom “backup toolbox” OCI image be published/pulled from by the cluster?
  - This impacts image name, auth, and how we pin digests.

## Decisions (confirmed by user, round 3)
- Toolbox image registry: GHCR
- Image visibility: public (no imagePullSecret)

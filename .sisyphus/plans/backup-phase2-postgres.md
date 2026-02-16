# Backup Phase 2: Tier-1 Resilience (Postgres)

## TL;DR

Daily `pg_dumpall` → zstd → upload off-cluster to Pi MinIO (`homelab-backup-postgres`, 14d retention). Weekly restore drill restores latest dump into isolated scratch Postgres (single Job pod) + smoke queries. Validate by forcing one-off Jobs and checking MinIO objects + restore logs.

**Deliverables**
- Daily backup CronJob (apps ns) uploading to MinIO
- Weekly restore-drill CronJob (apps ns) restoring into scratch pod + smoke validation
- K8s Secret(s) for MinIO creds sourced from `secrets/k8s-secrets.enc.yaml`
- GHCR public “backup-toolbox” image (pinned digest) containing: `pg_dumpall`, `psql`, `zstd`, `mc`, CA certs
- Validation runbook + evidence paths

**Effort**: Medium
**Parallel**: YES (2 waves)
**Critical path**: toolbox image → k8s secret → daily cronjob → restore drill → validation

---

## Context

### Source request
Plan + validation for `Phase 2: Tier-1 Resilience (Postgres)` only (from `.sisyphus/drafts/backup-strategy.md`).

### Confirmed repo facts
- Postgres: `modules/kubenix/apps/postgresql-18.nix` (Bitnami chart), namespace `apps`, release `postgresql-18`
- Host: `postgresql-18-hl:5432`
- Auth secret: `postgresql-auth` (key `admin-password`) from `modules/kubenix/apps/postgresql-auth.enc.nix`
- DB list source: `config/kubernetes.nix` → `homelab.kubernetes.databases.postgres`
- Existing ops targets exist but not MinIO-based: `make backup-postgres` / `make restore-postgres` → `modules/commands.nix`

### Confirmed design decisions
- Daily dump: `pg_dumpall`
- Compression: `zstd`
- Restore drill: scratch Postgres instance (isolated)
- Validation: smoke only
- Alerting: CronJob failure only
- Schedule: daily 02:30 + weekly Sun 03:00, TZ `America/Sao_Paulo`
- MinIO target: `http://10.10.10.209:9000`, bucket `homelab-backup-postgres`
- Object keys: `postgresql-18/YYYY/MM/DD/full.sql.zst` + `full.sql.zst.sha256`
- MinIO creds in-cluster: `secrets/k8s-secrets.enc.yaml` + kubenix Secret via `kubenix.lib.secretsFor`
- Toolbox image: public GHCR, pinned digest

### Defaults applied (override if desired)
- Toolbox image name: `ghcr.io/josevictor/backup-toolbox`
- CronJob names:
  - Daily backup: `postgres-backup`
  - Weekly restore drill: `postgres-restore-drill`
- K8s Secret names:
  - MinIO creds secret (env): `postgres-backup-s3-credentials`
- SOPS key names (in `secrets/k8s-secrets.enc.yaml`):
  - `minio_postgres_backup_access_key_id`
  - `minio_postgres_backup_secret_access_key`

---

## Work objectives

### Core objective
Prove Postgres can be recovered with RPO<=24h using off-cluster logical dumps + automated restore drills.

### Must-have
- Off-cluster backups in MinIO, 14-day retention, no secrets in git
- Weekly automated restore drill that fails loudly on any restore/validation error
- Deterministic tooling (pinned toolbox image digest; no `latest`)

### Must-NOT (guardrails)
- Do NOT edit `.k8s/*.yaml` directly (use kubenix + `make manifests`)
- Do NOT hardcode secrets anywhere (use `kubenix.lib.secretsFor` / `secretKeyRef`)
- Do NOT restore into prod Postgres or reuse prod PVCs
- Do NOT rely on “user manually verifies” for acceptance; agent-executable only

---

## Verification strategy (mandatory)

### Test decision
- Infra exists: N/A (this is infra/ops)
- Automated tests: None
- Primary verification: agent-executed QA via `make` + `kubectl` + `mc`/HTTP

### Evidence
- Store all evidence in: `.sisyphus/evidence/backup-phase2-postgres/`
  - `backup-job-logs.txt`
  - `minio-ls.txt`
  - `restore-job-logs.txt`
  - `restore-smoke-results.txt`

---

## Execution strategy (parallel waves)

Wave 1 (independent)
- Task 1: Verify prerequisites + cluster constraints
- Task 2: Create/publish pinned toolbox image
- Task 3: Add k8s MinIO creds secret wiring

Wave 2 (after 2+3)
- Task 4: Daily backup CronJob
- Task 5: Weekly restore-drill CronJob

Wave 3 (after 4+5)
- Task 6: Validation runbook + forced-run verification

---

## TODOs

> Notes for executor:
> - Flake eval uses git state; stage new files before `make manifests`.
> - If Cilium policies block egress, add a narrow allow rule (apps ns → 10.10.10.209:9000).

### 1) Prereq verification (versions, network, bucket)

**What to do**
- Identify actual Postgres server version deployed by `postgresql-18.nix` (image tag) and/or via `kubectl exec` into running pod.
- Verify cluster can reach MinIO endpoint from `apps` namespace (simple curl / `mc` in a temp pod).
- Verify bucket exists: `homelab-backup-postgres`.
- Verify bucket retention (ILM) is set to expire objects after 14 days.
- Verify whether CronJob `spec.timeZone` is supported by your k8s version; if not, convert cron to UTC and omit `timeZone`.
- Check if any NetworkPolicies / Cilium policies enforce default-deny egress; if yes, plan to add allow rule.

**Must NOT do**
- No `kubectl apply` for permanent config (GitOps only).

**Recommended agent profile**
- Category: `unspecified-high` (infra discovery)
- Skills: (none)

**References**
- `modules/kubenix/apps/postgresql-18.nix` (server image/version)
- `modules/kubenix/system/cilium.nix` (potential policy patterns)
- `.sisyphus/plans/backup-hub-identity-access.md` (MinIO endpoint/bucket conventions)

**Acceptance criteria (agent-executable)**
- [ ] Captured Postgres server version in `.sisyphus/evidence/backup-phase2-postgres/postgres-version.txt`
- [ ] Captured MinIO reachability proof from cluster in `.sisyphus/evidence/backup-phase2-postgres/minio-reachability.txt`
- [ ] Captured bucket existence/listing in `.sisyphus/evidence/backup-phase2-postgres/minio-bucket-check.txt`
- [ ] Captured ILM/retention check in `.sisyphus/evidence/backup-phase2-postgres/minio-ilm-check.txt` (expect: expire ~14d)

**QA scenarios**
Scenario: Prove MinIO reachable from apps namespace
  Tool: Bash (`kubectl run` or one-off Pod)
  Steps:
    1. Start temp pod in `apps` with a tiny image containing curl (or reuse toolbox once built)
    2. `curl -sS -I http://10.10.10.209:9000/minio/health/ready`
    3. Assert HTTP 200
    4. Save stdout to `.sisyphus/evidence/backup-phase2-postgres/minio-reachability.txt`

---

### 2) Build + publish “backup-toolbox” image (public GHCR) and pin digest

**What to do**
- Add build context in repo (e.g., `images/backup-toolbox/`) with Dockerfile.
- Contents (minimum): Postgres client tools (`pg_dumpall`, `psql`), `zstd`, `minio/mc`, CA certs, `bash`, `coreutils`.
- Publish to GHCR public: `ghcr.io/<you>/backup-toolbox:<version>`.
- Record immutable digest; use digest pinning in kubenix (no `latest`).
- Ensure Postgres client version is compatible (`pg_dumpall` >= server version).

**Must NOT do**
- No secrets in image.

**Recommended agent profile**
- Category: `developing-containers` (image build/publish)
- Skills: `developing-containers`

**References**
- Metis note: client/server version mismatch is critical
- Postgres docs (restore considerations): https://www.postgresql.org/docs/17/backup-dump.html

**Acceptance criteria**
- [ ] Image published to GHCR (public)
- [ ] Digest recorded in `.sisyphus/evidence/backup-phase2-postgres/toolbox-image-digest.txt`
- [ ] Running container proves tools exist:
  - `pg_dumpall --version`
  - `psql --version`
  - `zstd --version`
  - `mc --version`

**QA scenario**
Scenario: Toolbox image sanity
  Tool: Bash (docker/podman)
  Steps:
    1. Pull image by digest
    2. Run `pg_dumpall --version && psql --version && zstd --version && mc --version`
    3. Save output to `.sisyphus/evidence/backup-phase2-postgres/toolbox-image-smoke.txt`

---

### 3) Add MinIO creds into k8s secrets + kubenix Secret wiring

**What to do**
- Add new keys to `secrets/k8s-secrets.enc.yaml` for MinIO Postgres backup access (access key + secret key).
  - Default key names (change if you prefer):
    - `minio_postgres_backup_access_key_id`
    - `minio_postgres_backup_secret_access_key`
- Create kubenix secret module (e.g., `modules/kubenix/apps/postgres-backup-s3-credentials.enc.nix`) using `kubenix.lib.secretsFor`:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - (optional) `AWS_ENDPOINT_URL` or `MC_HOST_backup` (prefer explicit envs in job)
- Ensure CronJobs reference these via `valueFrom.secretKeyRef`.
- Run `make manifests` (pipeline) and verify generated encrypted secret exists and contains expected keys.

**Must NOT do**
- Do not copy creds from `hosts-secrets.enc.yaml` into plaintext; use `make secrets` to edit SOPS file.

**Recommended agent profile**
- Category: `writing-nix-code`
- Skills: `writing-nix-code`

**References**
- Secret pattern: `modules/kubenix/apps/s3-credentials.enc.nix`
- Homelab rule: env-var secretKeyRef requires explicit kubenix Secret definition (`.docs/rules.md`)

**Acceptance criteria**
- [ ] `make manifests` succeeds
- [ ] Decrypted generated secret shows both keys present (capture output to `.sisyphus/evidence/backup-phase2-postgres/generated-secret-check.txt`)

---

### 4) Implement daily backup CronJob (apps)

**What to do**
- Add kubenix module (e.g., `modules/kubenix/apps/postgres-backup.nix`) defining CronJob:
  - Schedule: `02:30` in `America/Sao_Paulo` (or UTC fallback)
  - ConcurrencyPolicy: `Forbid`
  - BackoffLimit: small (e.g., 2)
  - History limits: keep low
  - Uses toolbox image pinned digest
  - Env:
    - `PGHOST=postgresql-18-hl`
    - `PGPORT=5432`
    - `PGUSER=postgres`
    - `PGPASSWORD` from `postgresql-auth:admin-password`
    - MinIO: endpoint `http://10.10.10.209:9000`
    - S3 creds from Task 3 secret
- Script outline:
  1. Create date prefix: `YYYY/MM/DD`
  2. `pg_dumpall` → write to `/tmp/full.sql`
  3. `zstd` → `/tmp/full.sql.zst`
  4. `sha256sum` → `/tmp/full.sql.zst.sha256`
  5. `mc alias set` via env (or `MC_HOST_*` env)
  6. Upload to tmp object key then move to final (avoid partial):
     - `.../full.sql.zst.tmp` then `mc mv` to `.../full.sql.zst`
     - same for `.sha256`

**Notes**
- If dumps get big, switch to streaming (avoid `/tmp` blowup): `pg_dumpall | zstd | mc pipe ...`.
- Set explicit resource requests/limits (incl `ephemeral-storage`).

**Must NOT do**
- Do not upload directly to final key without tmp+rename (partial upload hazard).

**Recommended agent profile**
- Category: `writing-nix-code`
- Skills: `writing-nix-code`

**References**
- Postgres host/service pattern: `modules/kubenix/apps/postgresql-auth.enc.nix` (bootstrap Job uses `PGPASSWORD` secretKeyRef)
- Postgres module: `modules/kubenix/apps/postgresql-18.nix`
- MinIO mc docs: https://min.io/docs/minio/linux/reference/minio-mc/mc-pipe.html

**Acceptance criteria**
- [ ] `make check` passes
- [ ] `make manifests` passes
- [ ] After Flux sync, CronJob exists in cluster and is `Active` on schedule

**QA scenarios**
Scenario: Forced daily backup run uploads objects
  Tool: Bash
  Steps:
    1. `kubectl -n apps create job --from=cronjob/postgres-backup backup-manual-1`
    2. Wait Job Complete (timeout 10m)
    3. Get logs; save to `.sisyphus/evidence/backup-phase2-postgres/backup-job-logs.txt`
    4. List MinIO prefix for today; save to `.sisyphus/evidence/backup-phase2-postgres/minio-ls.txt`
    5. Assert both `full.sql.zst` and `full.sql.zst.sha256` exist and size > 0
    6. Download both files and run `sha256sum -c` (save output to `.sisyphus/evidence/backup-phase2-postgres/backup-sha-verify.txt`)

---

### 5) Implement weekly restore-drill CronJob (apps) using isolated scratch Postgres pod

**What to do**
- Add kubenix module (e.g., `modules/kubenix/apps/postgres-restore-drill.nix`) defining CronJob:
  - Schedule: Sun 03:00 in `America/Sao_Paulo` (or UTC fallback)
  - Pod contains 2 containers sharing `emptyDir`:
    - `scratch-postgres`: runs Postgres server on localhost (emptyDir data), image pinned by digest and major-version compatible
    - `restore`: toolbox image, downloads latest dump from MinIO, restores into localhost scratch, then runs smoke queries
- Restore logic:
  1. Determine latest object under `postgresql-18/` (e.g., `mc ls --recursive --json` then pick newest)
  2. Download `full.sql.zst` + `.sha256`
  3. Verify sha256
  4. `zstd -dc full.sql.zst | psql -v ON_ERROR_STOP=1 ...` into scratch
  5. Smoke checks (examples):
     - `psql -Atc 'SELECT 1'`
     - list DBs: `SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;` and assert expected DB names exist (from `config/kubernetes.nix` list)
     - save smoke output to `.sisyphus/evidence/backup-phase2-postgres/restore-smoke-results.txt`

**Guardrails**
- Scratch DB must be localhost-only (no Service), and namespace isolated if you create one.

**Recommended agent profile**
- Category: `writing-nix-code`
- Skills: `writing-nix-code`

**References**
- DB list: `config/kubernetes.nix` → `homelab.kubernetes.databases.postgres`
- Postgres dump/restore docs: https://www.postgresql.org/docs/18/app-pg-dumpall

**Acceptance criteria**
- [ ] `make check` passes
- [ ] `make manifests` passes
- [ ] Forced restore drill job completes successfully and smoke checks pass

**QA scenarios**
Scenario: Forced weekly restore drill restores + validates
  Tool: Bash
  Steps:
    1. Ensure at least 1 backup exists in MinIO (Task 4 scenario)
    2. `kubectl -n apps create job --from=cronjob/postgres-restore-drill restore-manual-1`
    3. Wait Job Complete (timeout 20m)
    4. Save logs to `.sisyphus/evidence/backup-phase2-postgres/restore-job-logs.txt`
    5. Assert logs contain: “sha256 OK”, “restore OK”, “smoke OK”

Scenario: Restore drill fails on sha mismatch
  Tool: Bash
  Steps:
    1. Temporarily point drill to a wrong `.sha256` key (via env override or test-only job)
    2. Run one-off job
    3. Assert Job fails (status Failed) and logs contain “sha256 mismatch”

---

### 6) Validation runbook + minimal alert check

**What to do**
- Add a short runbook section (inside plan-referenced markdown OR small doc file) describing:
  - How to force-run backup and drill jobs
  - Where to look for artifacts in MinIO
  - Expected log markers
- Verify existing monitoring already alerts on CronJob/Job failures (if kube-prometheus stack installed). If not, add minimal rule (optional; only if existing pattern present).

**Recommended agent profile**
- Category: `writing`
- Skills: none

**Acceptance criteria**
- [ ] Runbook exists and is referenced from this plan (path + section)
- [ ] Evidence files present in `.sisyphus/evidence/backup-phase2-postgres/` from Task 4+5 QA runs

---

## Success criteria (end state)

- [ ] Daily backup CronJob consistently uploads `full.sql.zst` + `.sha256` to MinIO (14d retention enforced by ILM)
- [ ] Weekly restore drill completes successfully at least once and validates expected DB presence
- [ ] Forced-run validation steps produce evidence files under `.sisyphus/evidence/backup-phase2-postgres/`
- [ ] All changes are GitOps (kubenix + `make manifests`), no direct `.k8s` edits, no plaintext secrets

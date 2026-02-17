# Phase 4 Plan: Storage Mirror & System State (RGW mirror + k3s etcd offload)

## TL;DR

Deliver Phase 4 only:
- **RGW mirror**: in-cluster **CronJob** runs `rclone` to mirror selected Ceph RGW buckets → Pi MinIO bucket `homelab-backup-rgw`.
- **System state**: on each **k8s control-plane node**, a **systemd timer** uploads new k3s etcd snapshots from `/var/lib/rancher/k3s/server/db/snapshots/` → Pi MinIO bucket `homelab-backup-etcd`.

Effort: Medium. Parallel: YES (2 waves).

---

## Context (from draft)

- Offsite target: **Pi MinIO** on LAN HTTP (`http://10.10.10.209:9000`), external HDD.
- Buckets already provisioned on Pi: `homelab-backup-rgw`, `homelab-backup-etcd` (versioning + ILM 14d).
- Repo constraints: **Nix + kubenix**, never edit `.k8s/` directly, secrets via **SOPS** (`kubenix.lib.secretsFor` / sops-nix), no hardcoded secrets.
- k3s snapshots: default dir `/var/lib/rancher/k3s/server/db/snapshots/`.

---

## Scope

IN:
- Add RGW→MinIO mirror job(s) + creds wiring.
- Add k3s snapshot offload (host-level service/timer) + creds wiring.
- Add **validation steps** to prove both are working.

OUT:
- Any destructive Ceph ops (finalizers/CR deletion/etc.).
- Any k3s restore / `--cluster-reset` execution.
- TLS hardening for MinIO (explicitly accepted HTTP LAN).

---

## Verification Strategy (agent-executed)

No unit tests expected (infra config). Verification = commands + evidence files.

Evidence location (executor MUST capture):
- `.sisyphus/evidence/phase4-rgw-mirror-*.txt`
- `.sisyphus/evidence/phase4-etcd-offload-*.txt`

---

## Execution Strategy (parallel waves)

Wave 1 (foundation/credentials): Tasks 1,2,3 can run in parallel.
Wave 2 (jobs/services + validation): Tasks 4,5,6 can run in parallel once creds exist.

---

## TODOs (Phase 4 only)

### 1) Decide + wire **destination MinIO creds** for RGW mirror into k8s

**What to do**:
- Add SOPS keys to **k8s secrets source** (currently present in host secrets only):
  - `minio_rgw_access_key_id`
  - `minio_rgw_secret_access_key`
- Create kubenix Secret module for the CronJob, e.g.:
  - `modules/kubenix/apps/rgw-mirror-s3-credentials.enc.nix`
  - Secret name suggestion: `rgw-mirror-s3-credentials` with keys `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- Confirm **source RGW creds** to use:
  - Prefer reusing existing `modules/kubenix/apps/s3-credentials.enc.nix` Secret `s3-credentials` (Ceph RGW access).

**Must NOT do**:
- Do not hardcode keys in `.nix` or scripts.
- Do not reuse postgres MinIO creds.

**Recommended Agent Profile**:
- Category: `quick` (Nix/kubenix secret plumbing).
- Skills: none.

**Parallelization**: YES (Wave 1). Blocks: Task 4.

**References**:
- `modules/profiles/backup-server.nix` bucket+secret naming (`homelab-backup-rgw`, `minio_rgw_*`).
- `modules/kubenix/apps/postgres-backup-s3-credentials.enc.nix` secret pattern (`kubenix.lib.secretsFor`, stringData keys).
- `.docs/rules.md` secrets + flake git-state rule (new files must be `git add` before `make manifests`).

**Acceptance Criteria**:
- `secrets/k8s-secrets.enc.yaml` contains `minio_rgw_access_key_id` + `minio_rgw_secret_access_key`.
- New kubenix secret module exists and is referenced by the RGW mirror CronJob.

**QA Scenarios**:
```
Scenario: k8s secret keys available for vals injection
  Tool: Bash
  Steps:
    1. sops -d secrets/k8s-secrets.enc.yaml | grep -E 'minio_rgw_(access_key_id|secret_access_key)'
  Expected Result: both keys printed (values redacted in evidence if needed)
  Evidence: .sisyphus/evidence/phase4-rgw-secret-keys.txt
```

---

### 2) Decide + wire **destination MinIO creds** for etcd offload on control-plane nodes

**What to do**:
- Ensure these SOPS keys are declared for **control-plane hosts** (host secrets already have them):
  - `minio_etcd_access_key_id`
  - `minio_etcd_secret_access_key`
- Add sops-nix declarations (likely `modules/common/sops.nix` or a dedicated module) so cp nodes get:
  - `/run/secrets/minio_etcd_access_key_id`
  - `/run/secrets/minio_etcd_secret_access_key`

**Must NOT do**:
- Do not place MinIO creds in world-readable files.

**Recommended Agent Profile**:
- Category: `quick`.

**Parallelization**: YES (Wave 1). Blocks: Task 5.

**References**:
- `modules/profiles/backup-server.nix` shows existing sops-nix pattern for MinIO creds on Pi.
- `modules/profiles/k8s-control-plane.nix` (control-plane profile to extend/enable).

**Acceptance Criteria**:
- On a control-plane node, both `/run/secrets/minio_etcd_access_key_id` and `/run/secrets/minio_etcd_secret_access_key` exist with mode 0400.

**QA Scenarios**:
```
Scenario: etcd MinIO creds present on cp node
  Tool: Bash (ssh)
  Steps:
    1. ssh root@lab-alpha-cp 'ls -l /run/secrets/minio_etcd_*'
  Expected Result: both files exist, owner root, perms 0400
  Evidence: .sisyphus/evidence/phase4-etcd-secrets-on-cp.txt
```

---

### 3) Confirm **which RGW buckets** are mirrored

**Decision (confirmed)**:
- Mirror **all RGW buckets** reachable by the source creds.

**Recommended Agent Profile**:
- Category: `quick`.

**Parallelization**: YES (Wave 1). Blocks: Task 4.

**Acceptance Criteria**:
- Bucket allow-list exists in CronJob config (env var `RGW_BUCKETS=b1,b2,...` or similar).

---

### 4) Implement **RGW→MinIO mirror CronJob** (rclone)

**What to do**:
- Add `modules/kubenix/apps/rgw-mirror.nix` CronJob in applications namespace.
- Use `rclone` container (pin digest).
- Configure 2 S3 remotes (Ceph RGW source + MinIO dest) via env vars (avoid config files):
  - Source endpoint: use repo’s Ceph RGW service endpoint.
  - Dest endpoint: `http://10.10.10.209:9000`.
- Implement script behavior:
  - Iterate allow-listed buckets.
  - For each bucket:
    - **Initial mode (1-2 days)**: `rclone copy` from `ceph:<bucket>` → `minio:homelab-backup-rgw/<bucket>`.
    - **Steady state**: switch to `rclone sync` to maintain mirror.
  - Safety flags: `--checksum --delete-after --retries 10 --retries-sleep 5s --log-level INFO`.
  - Performance defaults: `--transfers 4 --checkers 8` (tune later).
  - Emit a per-run report (counts + duration) and upload the report to MinIO under `homelab-backup-rgw/_reports/YYYY-MM-DD/`.
- Schedule: daily 04:00 (staggered after Postgres+Velero).

**Must NOT do**:
- No `--delete-before`.
- No broad wildcard mirroring without allow-list unless explicitly chosen.

**Recommended Agent Profile**:
- Category: `unspecified-high` (kubenix CronJob + robust scripting).
- Skills: none.

**Parallelization**: YES (Wave 2). Blocked by: 1,3.

**References**:
- `modules/kubenix/apps/postgres-backup.nix` CronJob conventions (timezone, Forbid concurrency, secretKeyRef env, resource limits, atomic upload pattern).
- `modules/kubenix/apps/s3-credentials.enc.nix` source RGW creds secret pattern.
- `modules/kubenix/_lib/default.nix` RGW endpoint convention.
- rclone docs: `rclone sync`, `rclone check`, `rclone s3`.

**Acceptance Criteria**:
- `make manifests` generates a CronJob for rgw mirror and required Secret(s).
- Manual run (Job from CronJob) mirrors a test object from RGW to MinIO.

**QA Scenarios**:
```
Scenario: mirror copies a known test object (happy path)
  Tool: Bash
  Steps:
    1. kubectl -n applications run rclone-src --rm -i --restart=Never --image=rclone/rclone:latest -- \
         sh -lc 'echo phase4-test | rclone rcat ceph:<BUCKET>/phase4-test-$(date +%s).txt'
    2. kubectl -n applications create job --from=cronjob/rgw-mirror rgw-mirror-manual-$(date +%s)
    3. kubectl -n applications logs -f job/rgw-mirror-manual-*
    4. kubectl -n applications run rclone-dst --rm -i --restart=Never --image=rclone/rclone:latest -- \
         sh -lc 'rclone lsf minio:homelab-backup-rgw/<BUCKET>/ | grep phase4-test'
  Expected Result: object name present in destination listing
  Evidence: .sisyphus/evidence/phase4-rgw-mirror-happy.txt

Scenario: deletion safety (should not delete before transfer)
  Tool: Bash
  Steps:
    1. Run mirror with flags containing --delete-after (confirm via logs)
  Expected Result: logs show --delete-after; no --delete-before
  Evidence: .sisyphus/evidence/phase4-rgw-mirror-delete-safety.txt
```

---

### 5) Implement **k3s etcd snapshot offload** (host-level systemd timer)

**What to do**:
- Add a host-level service+timer enabled on all control-plane nodes (recommended placement: extend `modules/profiles/k8s-control-plane.nix` or add `modules/services/k3s-etcd-offload.nix` and enable from the profile).
- Service behavior:
  - Read snapshots from `/var/lib/rancher/k3s/server/db/snapshots/`.
  - Upload new snapshots to `homelab-backup-etcd/<hostname>/` on MinIO.
  - Avoid partial uploads: ignore files modified in last N minutes OR copy to temp dir before upload.
  - Upload a `.sha256` alongside each snapshot.
  - Maintain local state to avoid re-upload (e.g., `StateDirectory=etcd-offload`).
- Hardening:
  - Make snapshot path read-only (systemd `ReadOnlyPaths=`).
  - Minimal PATH deps (include `minio-client` + transitive deps; see repo lessons).
- Timer schedule: hourly with randomized delay.

**Must NOT do**:
- MUST NOT disable k3s.
- MUST NOT run `k3s server --cluster-reset ...` as “validation”.
- MUST NOT write into `/var/lib/rancher/k3s/...`.

**Recommended Agent Profile**:
- Category: `unspecified-high` (NixOS systemd hardening + backup logic).

**Parallelization**: YES (Wave 2). Blocked by: 2.

**References**:
- k3s docs: https://docs.k3s.io/cli/etcd-snapshot (paths/commands).
- `modules/profiles/backup-server.nix` shows MinIO bootstrap + sops-nix secret usage + explicit PATH deps.
- `.docs/rules.md` systemd PATH minimal lesson + transitive deps.

**Acceptance Criteria**:
- On each control-plane node: `systemctl status etcd-offload.timer` is active.
- Manual run uploads at least 1 snapshot + sha256 to MinIO.

**QA Scenarios**:
```
Scenario: manual offload uploads latest snapshot (happy path)
  Tool: Bash (ssh)
  Steps:
    1. ssh root@lab-alpha-cp 'ls -lh /var/lib/rancher/k3s/server/db/snapshots/ | tail -n +1'
    2. ssh root@lab-alpha-cp 'systemctl start etcd-offload.service'
    3. ssh root@lab-alpha-cp 'journalctl -u etcd-offload.service --no-pager | tail -n 200'
    4. ssh root@lab-pi-bk 'mc ls pi/homelab-backup-etcd/$(hostname -s)/ | tail -n 50'
  Expected Result: at least one new snapshot + matching .sha256 visible in MinIO
  Evidence: .sisyphus/evidence/phase4-etcd-offload-happy.txt

Scenario: safety: service cannot write into k3s dir
  Tool: Bash (ssh)
  Steps:
    1. ssh root@lab-alpha-cp 'systemd-analyze security etcd-offload.service | head -n 50'
  Expected Result: hardening present; snapshot dir is read-only; no writable paths under /var/lib/rancher/k3s
  Evidence: .sisyphus/evidence/phase4-etcd-offload-hardening.txt
```

---

### 6) Add operator-facing **validation runbook/Make targets** (non-interactive)

**What to do**:
- Add simple commands (README snippet or Makefile targets) to:
  - Trigger RGW mirror ad-hoc job.
  - Trigger etcd offload service on a chosen cp node.
  - Verify presence + non-zero size + sha256 match.

**Recommended Agent Profile**:
- Category: `writing` (concise runbook) OR `quick` (Makefile targets).

**Parallelization**: YES (Wave 2).

**Acceptance Criteria**:
- Single command path exists to (a) run each job, (b) verify artifacts exist.

---

## Final Verification (must pass before marking Phase 4 done)

1) RGW mirror:
- Create a test object in a mirrored bucket (source RGW).
- Run mirror job.
- Verify object exists in `pi/homelab-backup-rgw/<bucket>/...`.

2) etcd offload:
- Confirm snapshots exist locally on at least one cp node (`ls /var/lib/.../snapshots`).
- Run `etcd-offload.service`.
- Verify new snapshot + sha256 exists in `pi/homelab-backup-etcd/<hostname>/`.

---

## Decisions (Phase 4)

- RGW buckets: **all**.
- First-run safety: **copy → sync**.

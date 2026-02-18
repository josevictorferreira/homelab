# Proton Drive daily backup for shared subfolders

## TL;DR
> **Goal**: daily backup `notetaking/`, `images/`, `backup/` from CephFS shared PVC to Proton Drive.
>
> **Reality check**: Proton Drive has no official headless Linux API/client; automation is brittle. Plan uses **2-stage**: (1) reliable on-prem copy to existing **Pi MinIO S3** (already a repo pattern), (2) **best-effort** sync MinIO → Proton Drive using an OSS Proton Drive client, with monitoring/alerts.
>
> **Deliverables**:
> - New CronJob to create daily `tar.zst + sha256 + manifest` archives from `cephfs-shared-storage-root` subfolders → MinIO bucket.
> - New CronJob/service to sync those archives → Proton Drive (experimental).
> - Grafana alert rules for staleness/failures.

**Estimated Effort**: Medium
**Parallel Execution**: YES (3 waves)
**Critical Path**: Decide Proton tooling/auth → build + deploy CronJobs → verify backups + alerting

---

## Context

### Original Request
- In the shared folder, back up only subfolders: `notetaking`, `images`, `backup`.
- Run daily.
- Store in Proton Drive (Proton subscription active).

### Current Homelab Conventions (repo evidence)
- “Shared folder” in k8s is CephFS static PVC **`cephfs-shared-storage-root`** (`modules/kubenix/apps/shared-storage-pvc.nix`).
- Backup patterns already exist:
  - CronJobs that upload artifacts to off-cluster Pi MinIO (S3):
    - `modules/kubenix/apps/postgres-backup.nix` (zstd + sha256 + atomic rename)
    - `modules/kubenix/apps/rgw-mirror.nix` (rclone with env-defined remotes + report)
  - Host timer for etcd snapshot offload: `modules/profiles/k8s-control-plane.nix`
  - Backup alerting patterns: `modules/kubenix/monitoring/grafana-backup-alerts.nix`

### External Constraints (Proton Drive)
- No official headless Linux API/CLI for Proton Drive; no WebDAV/SFTP.
- rclone ProtonDrive backend exists but is **Tier-5 / deprecated/unsupported** (API break risk).
- Viable OSS client exists but is **non-official** (example: `DamianB-BitFlipper/proton-drive-sync`).

### Defaults Applied (override if wanted)
### Decisions (confirmed)
- Offsite approach: **MinIO first**, then **best-effort Proton Drive** sync.
- Proton sync runs: **in-cluster job**.
- Proton 2FA: **NO**.
- Retention: **14 daily** archives.
- Source paths: at PVC root: `/shared/notetaking`, `/shared/images`, `/shared/backup`.

### Defaults Applied (override if wanted)
- Consistency: **crash-consistent** (no CephFS snapshot integration).
- Encryption: **no extra encryption** on the MinIO copy (Proton copy is client-side encrypted by Proton tooling).

---

## Work Objectives

### Core Objective
Create a daily, automated, **recoverable** backup of selected shared subfolders and keep an offsite copy in Proton Drive.

### Concrete Deliverables
- Daily archive objects in MinIO bucket (authoritative first copy).
- Daily archive objects in Proton Drive (second copy; best-effort).
- Monitoring + alerts for both stages.

### Must NOT Have (guardrails)
- No plaintext secrets in git; **no placeholders** like `REPLACE_ME`.
- Do not edit `.k8s/*.yaml` directly; only kubenix Nix + `make manifests`.
- Do not touch Ceph/Rook CRs/finalizers.
- Avoid direct `kubectl apply` for persistent changes; GitOps via repo only.

---

## Verification Strategy (MANDATORY)

> **Zero human verification**: all checks are agent-executed commands.

### Test Decision
- **Infrastructure exists**: Nix + kubenix + `make manifests` validation; no unit-test framework expected for Nix.
- **Automated tests**: None (use build/eval + runtime QA scenarios).

### QA Policy
Every task includes:
- `make manifests` (where relevant)
- runtime checks (`mc ls`, checksum verify, log inspection)
- evidence saved under `.sisyphus/evidence/`

---

## Execution Strategy

### Parallel Execution Waves

Wave 1 (foundation + local reliable backup)
├── T1: Validate shared subfolder paths exist (sanity check)
├── T2: MinIO bucket + creds (least-privilege) for shared-archives
├── T3: Backup artifact contract (tar+zstd+manifest+sha256+atomic upload)
├── T4: Kubenix Secret wiring for S3 creds + optional report path
├── T5: CronJob: shared-subfolders → MinIO (mount PVC, RO)
└── T6: Restore drill job/runbook (MinIO archive → scratch)

Wave 2 (monitoring)
├── T7: Grafana alert rules for shared backup CronJob staleness/failures
├── T8: (Optional) dashboard panel for shared backups
└── T9: Add MinIO bucket usage alert (if desired)

Wave 3 (Proton Drive offsite copy)
├── T10: Proton approach decision + auth bootstrap plan (DECISIONS)
├── T11: Proton sync workload (MinIO → Proton) + state PVC + report
└── T12: Alerts for Proton sync staleness/failure

Critical Path: T2/T3 → T4 → T5 → T7 → T10 → T11 → T12

### Dependency Matrix
| Task | Depends On | Blocks | Wave |
|------|------------|--------|------|
| T1 | — | T5 | 1 |
| T2 | — | T5 | 1 |
| T3 | — | T5 | 1 |
| T4 | T2 | T5 | 1 |
| T5 | T1,T3,T4 | T6,T7,T11 | 1 |
| T6 | T5 | — | 1 |
| T7 | T5 | T12 | 2 |
| T8 | — | — | 2 |
| T9 | — | — | 2 |
| T10 | — | T11 | 3 |
| T11 | T1,T5,T10 | T12 | 3 |
| T12 | T7,T11 | — | 3 |

---

## TODOs

> Each task includes: references + acceptance criteria + agent-executed QA scenarios.

- [ ] T1. Validate source paths exist (sanity)

  **What to do**:
  - Confirm these exist in PVC root:
    - `/shared/notetaking/`
    - `/shared/images/`
    - `/shared/backup/`

  **References**:
  - `modules/kubenix/apps/shared-storage-pvc.nix` (PVC name: `cephfs-shared-storage-root`).
  - Example mount usage: `modules/kubenix/apps/sftpgo.nix` mounts PVC at `/mnt/shared_storage`.

  **Acceptance Criteria**:
  - [ ] Command output in evidence shows the 3 folders exist (or explicitly shows which is missing).

  **QA Scenarios**:
  ```
  Scenario: Validate folders exist in mounted PVC
    Tool: Bash (kubectl)
    Steps:
      1. kubectl -n apps create -f - <<'YAML'
         apiVersion: v1
         kind: Pod
         metadata:
           name: tmp-shared-ls
         spec:
           restartPolicy: Never
           containers:
             - name: c
               image: alpine:3.20
               command: ["sh","-lc"]
               args:
                 - |
                   set -e
                   ls -la /shared
                   ls -la /shared/notetaking || true
                   ls -la /shared/images || true
                   ls -la /shared/backup || true
               volumeMounts:
                 - name: shared
                   mountPath: /shared
                   readOnly: true
           volumes:
             - name: shared
               persistentVolumeClaim:
                 claimName: cephfs-shared-storage-root
         YAML
      2. kubectl -n apps wait --for=condition=Ready pod/tmp-shared-ls --timeout=10m
      3. kubectl -n apps logs pod/tmp-shared-ls | tee .sisyphus/evidence/T1-shared-ls.txt
      4. kubectl -n apps delete pod/tmp-shared-ls
      2. Assert: entries for notetaking/images/backup exist
    Evidence: .sisyphus/evidence/T1-shared-ls.txt
  ```

- [ ] T2. MinIO bucket + creds for shared archives

  **What to do**:
  - Create MinIO bucket (suggest): `homelab-backup-shared-archives`.
  - Create restricted MinIO user/policy for write-only to that bucket prefix.
  - Store credentials in SOPS (`secrets/k8s-secrets.enc.yaml`) and expose to k8s as Secret (kubenix pattern).

  **Must NOT do**:
  - No plaintext creds committed; no manual kubectl edits to Secrets.

  **References**:
  - Existing credential secret patterns:
    - `modules/kubenix/apps/postgres-backup.nix` (S3 env vars via secretKeyRef).
    - `modules/kubenix/apps/rgw-mirror.nix` (rclone creds secret).
  - Secrets pipeline rules: `AGENTS.md` + `.docs/rules.md` (SOPS + `make manifests`).

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds.
  - [ ] Generated encrypted secret exists under `.k8s/` (SOPS) containing required keys (no plaintext in git).

  **QA Scenarios**:
  ```
  Scenario: Validate MinIO creds can write and list
    Tool: Bash
    Steps:
      1. kubectl -n apps create -f - <<'YAML'
         apiVersion: batch/v1
         kind: Job
         metadata:
           name: tmp-shared-mc-canary
         spec:
           backoffLimit: 0
           template:
             spec:
               restartPolicy: Never
               containers:
                 - name: mc
                   image: minio/mc:RELEASE.2024-10-02T08-27-28Z
                   env:
                     - name: AWS_ACCESS_KEY_ID
                       valueFrom:
                         secretKeyRef:
                           name: shared-subfolders-backup-s3-credentials
                           key: AWS_ACCESS_KEY_ID
                     - name: AWS_SECRET_ACCESS_KEY
                       valueFrom:
                         secretKeyRef:
                           name: shared-subfolders-backup-s3-credentials
                           key: AWS_SECRET_ACCESS_KEY
                   command: ["sh","-lc"]
                   args:
                     - |
                       set -euo pipefail
                       mc alias set shared http://10.10.10.209:9000 "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"
                       mc mb --ignore-existing shared/homelab-backup-shared-archives
                       echo test | mc pipe shared/homelab-backup-shared-archives/_canary.txt
                       mc stat shared/homelab-backup-shared-archives/_canary.txt
         YAML
      2. kubectl -n apps wait --for=condition=complete job/tmp-shared-mc-canary --timeout=10m
      3. kubectl -n apps logs job/tmp-shared-mc-canary | tee .sisyphus/evidence/T2-mc-canary.txt
      4. kubectl -n apps delete job/tmp-shared-mc-canary
    Evidence: .sisyphus/evidence/T2-mc-canary.txt
  ```

- [ ] T3. Backup artifact format + script (tar+zstd+manifest+sha256)

  **What to do**:
  - Define script contract used by CronJob:
    - Inputs: source root, folder list, dest bucket/prefix.
    - Outputs per run:
      - `shared-YYYY-MM-DD.tar.zst`
      - `shared-YYYY-MM-DD.tar.zst.sha256`
      - `shared-YYYY-MM-DD.manifest.json` (file list + sizes + mtime snapshot as observed)
  - Add exclusions (default): `.DS_Store`, `Thumbs.db`.
  - Ensure atomic upload pattern: upload as `*.tmp` then rename/move.
  - If “extra encryption on MinIO” chosen, define the encryption step here.

  **References**:
  - Atomic upload + checksum pattern: `modules/kubenix/apps/postgres-backup.nix`.

  **Acceptance Criteria**:
  - [ ] Script runs in chosen image and produces the 3 artifacts.

  **QA Scenarios**:
  ```
  Scenario: Produce archive from sample tree
    Tool: Bash
    Steps:
      1. Create temp dirs/files; run script locally in container.
      2. Assert: tar.zst exists; sha256 matches; manifest is valid JSON.
    Evidence: .sisyphus/evidence/T3-script-smoke.txt
  ```

- [ ] T4. Secret + wiring for shared backup CronJob (SOPS → kubenix)

  **What to do**:
  - Add/extend kubenix Secret definition for the CronJob’s MinIO creds.
  - Ensure secret keys are defined in kubenix config (see homelab rule re: env var secretKeyRef).

  **References**:
  - `.docs/rules.md`: “Kubenix secrets for env vars require explicit definition”.
  - `modules/kubenix/apps/postgres-backup.nix` (secretKeyRef patterns).

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds and generated `.k8s/...enc.yaml` contains the expected keys.

  **QA Scenarios**:
  ```
  Scenario: Validate secret keys exist in generated manifests
    Tool: Bash
    Steps:
      1. Run make manifests
      2. sops -d .k8s/.../shared-subfolders-backup-config.enc.yaml | grep -E 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY'
      3. Assert: both keys exist
    Evidence: .sisyphus/evidence/T4-secret-keys.txt
  ```

- [ ] T5. CronJob: shared subfolders → MinIO (daily)

  **What to do**:
  - Add kubenix app module (suggest file): `modules/kubenix/apps/shared-subfolders-backup.nix`.
  - CronJob in apps namespace with:
    - schedule daily (e.g. `0 1 * * *`), `concurrencyPolicy=Forbid`.
    - mount PVC `cephfs-shared-storage-root` **read-only** at `/shared`.
    - run backup script from T3.
    - upload artifacts to MinIO bucket created in T2.
  - Add secret wiring for S3 creds.

  **Must NOT do**:
  - Do not copy entire shared storage; only specified subfolders.

  **References**:
  - PVC name definition: `modules/kubenix/apps/shared-storage-pvc.nix`.
  - Mount pattern: `modules/kubenix/apps/sftpgo.nix`.
  - CronJob patterns: `modules/kubenix/apps/postgres-backup.nix` and `modules/kubenix/apps/rgw-mirror.nix`.

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds.
  - [ ] After reconciliation, CronJob exists and succeeds at least once.
  - [ ] MinIO contains today’s archive + sha256 + manifest under date prefix.

  **QA Scenarios**:
  ```
  Scenario: Validate CronJob exists + last schedule
    Tool: Bash (kubectl)
    Steps:
      1. kubectl -n apps get cronjob shared-subfolders-backup -o wide
      2. Assert: schedule matches plan; suspend=false
    Evidence: .sisyphus/evidence/T5-cronjob-get.txt

  Scenario: Validate archive integrity from MinIO
    Tool: Bash
    Steps:
      1. mc cat shared/homelab-backup-shared-archives/<today>/shared-<date>.tar.zst | zstd -d | tar -t > /dev/null
      2. Assert: exit code 0
    Evidence: .sisyphus/evidence/T5-archive-verify.txt
  ```

- [ ] T6. Restore drill (MinIO archive → scratch path) + runbook

  **What to do**:
  - Write a minimal restore drill procedure (download + verify sha + extract).
  - (Optional) create a k8s Job template or `make` target to run it.

  **References**:
  - Archive format from T3.

  **Acceptance Criteria**:
  - [ ] Restore drill can be executed without guesswork (exact commands).

  **QA Scenarios**:
  ```
  Scenario: Restore drill from a known archive
    Tool: Bash
    Steps:
      1. Download archive + sha256 from MinIO
      2. sha256sum -c
      3. zstd -d | tar -x to /tmp/shared-restore-drill
      4. Assert: expected top-level folders exist
    Evidence: .sisyphus/evidence/T6-restore-drill.txt
  ```

- [ ] T7. Monitoring: Grafana alerts for shared-subfolders-backup

  **What to do**:
  - Extend `modules/kubenix/monitoring/grafana-backup-alerts.nix` with rules:
    - CronJob staleness: `kube_cronjob_status_last_successful_time{namespace="apps", cronjob="shared-subfolders-backup"}` > 26h.
    - Job failure increase (if metrics exist) or use kube-state-metrics job status.
  - (Optional) add MinIO bucket size trend alert.

  **References**:
  - Existing alert patterns in `modules/kubenix/monitoring/grafana-backup-alerts.nix`.

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds.
  - [ ] Grafana rule group includes new alert(s).

  **QA Scenarios**:
  ```
  Scenario: Query Prometheus for last success timestamp
    Tool: Bash
    Steps:
      1. Query Prometheus API for kube_cronjob_status_last_successful_time for shared-subfolders-backup
      2. Assert: value is within last 26h after a manual run
    Evidence: .sisyphus/evidence/T7-prom-query.json
  ```

- [ ] T8. (Optional) Grafana dashboard panel for shared backups

  **What to do**:
  - Add a panel to existing backup dashboard(s) showing:
    - last successful time for shared-subfolders-backup
    - run duration and/or failures if metrics exist

  **Acceptance Criteria**:
  - [ ] Panel is present and queries are valid.

  **QA Scenarios**:
  ```
  Scenario: Validate PromQL query returns data
    Tool: Bash
    Steps:
      1. Query Prometheus API with the dashboard PromQL
      2. Assert: non-empty result
    Evidence: .sisyphus/evidence/T8-prom-panel-query.json
  ```

- [ ] T9. (Optional) MinIO bucket usage alert for shared archives

  **What to do**:
  - Add bucket/prefix usage alerts if metrics allow; otherwise skip.

  **Acceptance Criteria**:
  - [ ] Alert rule exists OR task explicitly skipped with rationale.

- [ ] T10. Proton Drive client + auth bootstrap (in-cluster)

  **What to do**:
  - Use **`DamianB-BitFlipper/proton-drive-sync`** (non-official) as Proton Drive client.
  - Auth bootstrap (no 2FA):
    - create a PVC for Proton client state/session cache
    - run a one-time Job (manual trigger) that performs initial login and persists state to PVC
    - subsequent sync CronJobs reuse the PVC state
  - Define Proton Drive destination folder (default): `/Backups/homelab/shared-archives/`.

  **Acceptance Criteria**:
  - [ ] A one-time bootstrap Job can log in and persist session state to PVC.
  - [ ] Tool can list target folder after bootstrap.

  **QA Scenarios**:
  ```
  Scenario: Tool smoke test in container
    Tool: Bash
    Steps:
      1. Build/pull image containing chosen tool
      2. Run 'tool --version' and 'tool help'
      3. Assert: exits 0
    Evidence: .sisyphus/evidence/T10-tool-smoke.txt
  ```

- [ ] T11. Proton sync workload (best-effort)

  **What to do**:
  - Implement k8s workload (CronJob daily after T4, or Deployment + internal scheduler) that:
    - lists new objects in MinIO prefix (today’s date)
    - downloads and uploads to Proton Drive destination
    - writes success marker and uploads a sync report back to MinIO under `_reports/`
  - Store Proton secrets/session state in:
    - SOPS secret for credentials (if required)
    - PVC for session/token cache
  - Add failure behavior:
    - non-zero exit on upload failure
    - retry/backoff and staleness alert

  **Must NOT do**:
  - Do not delete from Proton Drive automatically until confidence is high.

  **References**:
  - CronJob pattern + reporting: `modules/kubenix/apps/rgw-mirror.nix`.
  - MinIO upload + checksums: `modules/kubenix/apps/postgres-backup.nix`.
  - Proton Drive constraints refs:
    - https://proton.me/blog/proton-drive-sdk-preview
    - https://rclone.org/protondrive/

  **Acceptance Criteria**:
  - [ ] After a manual run, at least one archive appears in Proton Drive target folder.
  - [ ] A sync report is stored in MinIO for that run.
  - [ ] Alert rule exists for staleness/failure (either CronJob metrics or report timestamp).

  **QA Scenarios**:
  ```
  Scenario: Force-run Proton sync and verify remote
    Tool: Bash
    Steps:
      1. kubectl -n apps create job --from=cronjob/shared-subfolders-proton-sync shared-subfolders-proton-sync-manual
      2. kubectl -n apps wait --for=condition=complete job/shared-subfolders-proton-sync-manual --timeout=60m
      3. Use the chosen tool's 'list' command to assert destination contains today's archive
      4. Assert: sync report exists in MinIO _reports/<date>/
    Evidence: .sisyphus/evidence/T11-proton-sync.txt
  ```

- [ ] T12. Monitoring: Proton sync staleness/failure alerts

  **What to do**:
  - Add Grafana alert rule(s) for Proton sync:
    - CronJob staleness (preferred)
    - OR “report object exists for today” if CronJob metrics aren’t usable

  **Acceptance Criteria**:
  - [ ] Alerts exist and are queryable.

---

## Final Verification Wave (MANDATORY)

- [ ] F1. Plan compliance audit (oracle)
- [ ] F2. Nix/kubenix quality gate: `make check` + `make manifests` + no secret leaks
- [ ] F3. End-to-end backup validation: run T4 and validate archive integrity
- [ ] F4. Offsite validation: run T8 and verify Proton Drive object presence

---

## Commit Strategy

> Ask user before committing.

- Commit 1: `feat(backup): shared-subfolders -> minio`
- Commit 2: `feat(monitoring): shared backup alerts`
- Commit 3: `feat(backup): proton drive sync (experimental)`

---

## Success Criteria

- Daily MinIO archive exists for last 14 days and verifies (`zstd -d | tar -t`).
- Proton Drive contains same-day archive for last N days (best-effort) OR clear alert on staleness.
- Grafana alerts fire on staleness/failure; no silent failures.

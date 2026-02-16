# Plan: Phase 3 - Velero & Kopia Implementation

## TL;DR

> **Quick Summary**: Deploy Velero with Kopia (filesystem backup) to back up Kubernetes objects and PVC data to the Raspberry Pi MinIO server.
> 
> **Deliverables**:
> - `modules/kubenix/apps/velero.nix` (Helm release)
> - `modules/kubenix/apps/velero-config.enc.nix` (Secret configuration)
> - Updated `secrets/k8s-secrets.enc.yaml` (Instructions only)
> 
> **Estimated Effort**: Medium (due to testing)
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Secret update → Module creation → Deploy → Verify

---

## Context

### Original Request
Implement Phase 3 of the backup strategy: Filesystem & K8s Objects (Velero).

### Interview Summary
**Key Discussions**:
- **Target**: Raspberry Pi MinIO (`http://10.10.10.209:9000`), bucket `homelab-backup-velero`.
- **Method**: Velero + Kopia (FSB) for PVCs.
- **Schedule**: Daily at 03:00 AM.
- **Secrets**: Need to be added to K8s secrets from Pi host secrets.

### Metis Review
**Identified Gaps**:
- **Missing Secrets**: `minio_velero_access_key_id` and `minio_velero_secret_access_key` missing from `k8s-secrets.enc.yaml`.
- **Retention**: MinIO ILM is 14 days; Velero TTL should match.
- **Node Agent**: Must enable `deployNodeAgent` for Kopia.

---

## Work Objectives

### Core Objective
Deploy a functional Velero instance that backs up K8s resources and marked PVCs to the off-site Pi MinIO.

### Concrete Deliverables
- [x] `modules/kubenix/apps/velero.nix`
- [x] `modules/kubenix/apps/velero-config.enc.nix`
- [x] Verified backups in MinIO

### Definition of Done
- [x] `kubectl get pod -n velero` shows Running
- [x] `velero backup-location get` shows Available
- [x] Manual backup completes successfully
- [x] Data verified in MinIO bucket

### Must Have
- Kopia/FSB enabled (`deployNodeAgent: true`)
- S3 target configured for Pi MinIO
- Schedule enabled

### Must NOT Have (Guardrails)
- Do NOT use existing `hosts-secrets.enc.yaml` directly (must use `k8s-secrets.enc.yaml`).
- Do NOT expose MinIO publicly (keep LAN only).

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed.

### Test Decision
- **Infrastructure exists**: YES (Kubenix/Helm)
- **Automated tests**: Tests-after (Manual verification via script/CLI)
- **QA Policy**: Use `velero` CLI and `kubectl` to verify.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Configuration):
├── Task 1: Add secrets to k8s-secrets [quick] (User Action)
├── Task 2: Create Velero config secret module [quick]
└── Task 3: Create Velero app module [quick]

Wave 2 (Deployment & Verification):
├── Task 4: Deploy (make manifests & git push) [deep]
└── Task 5: Verify backup & restore [unspecified-high]

Critical Path: Task 1 → Task 2/3 → Task 4 → Task 5
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|------------|--------|------|
| 1 | — | 2, 3 | 1 |
| 2 | 1 | 4 | 1 |
| 3 | 1 | 4 | 1 |
| 4 | 2, 3 | 5 | 2 |
| 5 | 4 | — | 2 |

---

## TODOs

- [x] 1. **Add Secrets to k8s-secrets.enc.yaml**

  **What to do**:
  - Instruct user to run `make secrets` and add `minio_velero_access_key_id` and `minio_velero_secret_access_key`.
  - Values must match `secrets/hosts-secrets.enc.yaml` (Pi).
  - *Note: This is a user-dependent task, but critical.*

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `bash`

  **QA Scenarios**:
  ```
  Scenario: Verify secrets existence
    Tool: interactive_bash
    Preconditions: User has added secrets
    Steps:
      1. sops -d secrets/k8s-secrets.enc.yaml | grep "minio_velero_"
    Expected Result: Returns both keys (exit code 0)
  ```

- [x] 2. **Create Velero Config Module**

  **What to do**:
  - Create `modules/kubenix/apps/velero-config.enc.nix`.
  - Define `kubernetes.resources.secrets.velero-s3-credentials`.
  - Map `cloud` key to AWS credentials file format using `kubenix.lib.secretsFor`.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `writing-nix-code`

  **References**:
  - Pattern: `modules/kubenix/apps/postgres-backup-s3-credentials.enc.nix`

  **QA Scenarios**:
  ```
  Scenario: Check file syntax
    Tool: bash
    Steps:
      1. nix instanciate --eval modules/kubenix/apps/velero-config.enc.nix
    Expected Result: Success (or at least valid Nix syntax check)
  ```

- [x] 3. **Create Velero App Module**

  **What to do**:
  - Create `modules/kubenix/apps/velero.nix`.
  - Use `kubernetes.helm.releases.velero`.
  - Repo: `https://vmware-tanzu.github.io/helm-charts` (Chart: `velero`).
  - Values:
    - `configuration.backupStorageLocation`: `homelab-backup-velero` @ `http://10.10.10.209:9000`
    - `configuration.volumeSnapshotLocation.enabled: false` (using Kopia)
    - `deployNodeAgent: true` (Kopia)
    - `initContainers`: `velero-plugin-for-aws`
    - `credentials.useSecret: true` (ref `velero-s3-credentials`)

  **Recommended Agent Profile**:
  - **Category**: `writing`
  - **Skills**: `writing-nix-code`

  **QA Scenarios**:
  ```
  Scenario: Verify module logic
    Tool: bash
    Steps:
      1. Verify file exists
      2. Check for "deployNodeAgent" = true
  ```

- [x] 4. **Deploy Velero**

  **What to do**:
  - Run `make manifests`.
  - Check for errors.
  - Commit and push (GitOps).
  - Run `flux reconcile kustomization flux-system --with-source`.

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: `kubernetes-tools`, `git-master`

  **QA Scenarios**:
  ```
  Scenario: Verify Pods
    Tool: bash
    Steps:
      1. kubectl get pods -n velero
    Expected Result: velero-server and node-agent pods Running
  ```

- [x] 5. **Verify Backup & Restore**

  **What to do**:
  - Trigger manual backup: `velero backup create verification-test --wait`.
  - Verify success: `velero backup describe verification-test`.
  - Check MinIO: `mc ls s3-pi/homelab-backup-velero`.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: `bash`

  **QA Scenarios**:
  ```
  Scenario: Manual Backup
    Tool: interactive_bash
    Steps:
      1. velero backup create test-backup --wait
      2. velero backup get test-backup
    Expected Result: Phase: Completed
  ```

---

## Final Verification Wave

- [x] F1. **Plan Compliance Audit**
  Verify all files created and secrets referenced correctly.
  Output: `VERDICT: APPROVE`

- [x] F2. **Functional Check**
  Verify backup capability.
  Output: `Backup [PASS] | Restore [SKIPPED] | VERDICT: APPROVE`

---

## Success Criteria

### Verification Commands
```bash
velero backup get
kubectl get pods -n velero
```

### Final Checklist
- [x] Secrets added
- [x] Velero deployed
- [x] Node Agent running
- [x] Backup verified in MinIO

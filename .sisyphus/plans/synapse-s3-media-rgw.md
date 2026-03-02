# Synapse media -> Ceph RGW (S3) bucket (OBC creds) via synapse-s3-storage-provider

## TL;DR
> Switch Synapse media backend to Ceph RGW S3 bucket using `matrix-org/synapse-s3-storage-provider` installed via initContainer + PYTHONPATH.

**Deliverables**
- OBC bucket: `matrix-synapse-media`
- Synapse Helm values updated:
  - initContainer pip-installs provider into shared volume
  - Synapse env loads OBC creds + sets `PYTHONPATH`
  - `media_storage_providers` configured (store local+remote, prefix enabled)
- Migration runbook (agent-executable): upload existing media to S3; verify; then delete local

**Effort**: Medium
**Parallelism**: YES (3-4 waves)
**Critical path**: chart-capability check -> OBC bucket -> Synapse config+initContainer -> deploy -> migrate -> cleanup

---

## Context

### Original request
Use a Ceph-backed “object store bucket” as main asset/media storage for Matrix Synapse.

### Decisions (confirmed)
- Approach: **Synapse direct -> S3** via `synapse-s3-storage-provider` (not native)
- Topology: **single Synapse replica**
- Migration: **downtime OK**
- Creds: **OBC-generated Secret** (no SOPS static keys)
- Store: **local + remote media**
- Prefix: **YES** (e.g. `synapse/`)
- Module install: **initContainer pip install** + shared volume + `PYTHONPATH`
- Bucket name: **matrix-synapse-media**
- Post-migration: **delete local after verify**
- Include: **deploy + verify** (Flux reconcile + runtime checks)

### Repo references (patterns to follow)
- Synapse release: `modules/kubenix/apps/matrix.nix`
- Existing OBC pattern: `modules/kubenix/apps/open-webui.nix` (OBC + consume secret)
- OBC secret key pattern: `modules/kubenix/apps/linkwarden.nix` (reads `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
- RGW endpoint helper: `kubenix.lib.objectStoreEndpoint` (defined in `modules/kubenix/_lib/default.nix`)
- Provider docs: https://github.com/matrix-org/synapse-s3-storage-provider (README)

---

## Work Objectives

### Core objective
Make Ceph RGW S3 bucket the source of truth for Synapse media (uploads + remote cache), with a safe migration from current PVC-backed media.

### Must have
- OBC `matrix-synapse-media` becomes `Bound` and secret exists in apps namespace.
- Synapse starts with provider available on `PYTHONPATH` and loads `media_storage_providers` config.
- New media upload results in new object(s) under `s3://matrix-synapse-media/synapse/…`.
- Existing media migrated to S3; verified readable; then local media deleted (PVC kept for rollback window).

### Must NOT have (guardrails)
- NO direct edits to `.k8s/*.yaml` (generated).
- NO plaintext creds committed; NO new SOPS secrets for this (OBC-generated only).
- NO Ceph destructive ops (no finalizers changes; no rook-ceph namespace deletions).
- NO federation-related changes (out of scope).

---

## Verification Strategy

> Agent-executed only. Evidence saved under `.sisyphus/evidence/…`.

### Build/Config verification
- `make manifests` must succeed.
- (Optional) `make check` if already used in this repo’s workflow.

### Runtime verification (minimum)
- OBC bound + secret present.
- Synapse pod ready.
- Provider import works inside Synapse container.
- Upload test: create new media; confirm object exists in bucket.
- Read test: fetch that media via client/HTTP; confirm served.
- Migration test: old media still accessible after migration + local deletion.

---

## Execution Strategy

### Parallel waves (target 5-8 tasks/wave)

Wave 1 (discovery / de-risk)
- chart capability + correct value keys for initContainer/env/volumes
- confirm media store path + python env details in running pod
- confirm OBC secret key names and RGW endpoint behavior (path-style + checksum fallback)

Wave 2 (infra)
- add OBC resource for bucket

Wave 3 (synapse changes)
- add initContainer + shared volume + PYTHONPATH
- wire env from OBC secret
- configure `media_storage_providers`

Wave 4 (deploy + migrate)
- deploy via GitOps; verify
- migrate existing media; verify; delete local

---

## TODOs

- [ ] 1. Validate chart hooks + current runtime paths (de-risk)

  **What to do**:
  - Confirm the ananace/matrix-synapse chart value keys for:
    - initContainers
    - extra env / envFrom
    - extraVolumes / mounts
    - extraConfig injection for `homeserver.yaml`
  - Confirm current Synapse media store path inside the container (the directory that holds `local_content` etc.)
  - Confirm OBC secret key names (expect `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) in the apps namespace.
  - Decide whether provider needs checksum compatibility config for RGW (`request_checksum_calculation` / `response_checksum_validation`). Default: leave as provider default unless failures.

  **Must NOT do**:
  - Don’t change Synapse federation/registration behavior.

  **Recommended Agent Profile**:
  - **Category**: quick
  - **Skills**: [kubernetes-tools]
  - **Skills evaluated but omitted**: [playwright] (no UI work)

  **Parallelization**:
  - Can run in parallel: YES (with task 2 draft, but blocks actual deploy)
  - Wave: 1
  - Blocks: 3-6
  - Blocked by: none

  **References**:
  - `modules/kubenix/apps/matrix.nix` - where Synapse chart values are defined.
  - Provider README: https://github.com/matrix-org/synapse-s3-storage-provider (config keys + migration script).

  **Acceptance criteria**:
  - [ ] Plan updated with exact chart keys to use for initContainer/env/volumes.
  - [ ] Media store path recorded (absolute path).

  **QA scenarios**:
  ```
  Scenario: Verify chart supports required hooks
    Tool: Bash (repo inspection) + kubernetes-tools (cluster query if available)
    Steps:
      1. Inspect `modules/kubenix/apps/matrix.nix` values for initContainers/env/volumes support.
      2. If needed, consult chart values schema/docs.
    Expected: exact value keys confirmed.
    Evidence: .sisyphus/evidence/task-1-chart-keys.txt

  Scenario: Confirm media store path
    Tool: kubernetes-tools
    Steps:
      1. Exec into synapse pod; locate media store directory.
    Expected: directory path identified.
    Evidence: .sisyphus/evidence/task-1-media-path.txt
  ```

- [ ] 2. Add ObjectBucketClaim for Synapse media bucket

  **What to do**:
  - Add `ObjectBucketClaim` named `matrix-synapse-media` in the Synapse namespace.
  - Use `storageClassName = "rook-ceph-objectstore"`.
  - Set bucketName = `matrix-synapse-media`.

  **Must NOT do**:
  - Don’t create static creds in SOPS for this.

  **Recommended Agent Profile**:
  - **Category**: quick
  - **Skills**: [writing-nix-code]

  **Parallelization**:
  - Can run in parallel: YES (with task 1)
  - Wave: 2
  - Blocks: 3-6
  - Blocked by: none

  **References**:
  - OBC pattern: `modules/kubenix/apps/open-webui.nix` (how this repo declares `resources.objectbucketclaim`)
  - Rook objectstore SC: `modules/kubenix/storage/rook-ceph-cluster.nix` (`rook-ceph-objectstore`)

  **Acceptance criteria**:
  - [ ] `make manifests` produces an ObjectBucketClaim manifest.
  - [ ] After deploy: `kubectl get obc matrix-synapse-media ...` is `Bound`.

  **QA scenarios**:
  ```
  Scenario: OBC binds and secret appears
    Tool: Bash (kubectl)
    Steps:
      1. `kubectl get obc -n apps matrix-synapse-media -o wide`
      2. `kubectl get secret -n apps matrix-synapse-media -o yaml | grep AWS_ACCESS_KEY_ID`
    Expected: obc Bound; secret contains expected keys.
    Evidence: .sisyphus/evidence/task-2-obc-bound.txt
  ```

- [ ] 3. Add shared python module volume + initContainer pip install

  **What to do**:
  - Add an `emptyDir` volume (e.g., `synapse-python-modules`).
  - InitContainer runs `pip install --no-cache-dir --target /modules synapse-s3-storage-provider` (and deps if needed) into that volume.
  - Create an AWS config file to force S3 path-style (RGW-friendly):
    - Write `/modules/aws-config` with:
      - `[default]`
      - `s3 =`
      - `  addressing_style = path`
  - Mount volume into Synapse container at `/modules`.
  - Set `PYTHONPATH=/modules` in Synapse container env.
  - Set `AWS_CONFIG_FILE=/modules/aws-config`.
  - Set `AWS_EC2_METADATA_DISABLED=true`.

  **Must NOT do**:
  - Don’t bake creds into the initContainer.

  **Recommended Agent Profile**:
  - **Category**: general
  - **Skills**: [writing-nix-code, kubernetes-tools]

  **Parallelization**:
  - Can run in parallel: YES (with task 4)
  - Wave: 3
  - Blocks: 5-6
  - Blocked by: 1

  **References**:
  - Provider README: needs `s3_storage_provider.py` on `PYTHONPATH`.
  - Existing initContainer patterns: `modules/kubenix/apps/protonmail-bridge.nix`, `mautrix-*.nix`.

  **Acceptance criteria**:
  - [ ] Generated Deployment includes initContainer, volume, mount, and PYTHONPATH env.
  - [ ] After deploy: `python -c 'import s3_storage_provider'` succeeds inside Synapse container.

  **QA scenarios**:
  ```
  Scenario: Provider import works
    Tool: Bash (kubectl)
    Steps:
      1. `kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- python -c "import s3_storage_provider; print('ok')"`
    Expected: prints ok.
    Evidence: .sisyphus/evidence/task-3-provider-import.txt
  ```

- [ ] 4. Wire S3 config + creds into Synapse `media_storage_providers`

  **What to do**:
  - Update Synapse config in Helm values to include:
    - `media_storage_providers` with module `s3_storage_provider.S3StorageProviderBackend`
    - `store_local: true`, `store_remote: true`, `store_synchronous: true`
    - `config.bucket: matrix-synapse-media`
    - `config.endpoint_url: ${kubenix.lib.objectStoreEndpoint}`
    - `config.region_name: us-east-1`
    - `config.prefix: synapse/`
    - `config.access_key_id` and `secret_access_key` via env or config injection (prefer env-based boto3 resolution if chart supports envFrom)
  - If RGW checksum errors observed, set:
    - `request_checksum_calculation: when_supported`
    - `response_checksum_validation: when_supported`

  **Recommended Agent Profile**:
  - **Category**: general
  - **Skills**: [writing-nix-code]

  **Parallelization**:
  - Can run in parallel: YES (with task 3)
  - Wave: 3
  - Blocks: 5-6
  - Blocked by: 1-2

  **References**:
  - Provider README config example.
  - RGW endpoint helper: `modules/kubenix/_lib/default.nix`.

  **Acceptance criteria**:
  - [ ] Synapse starts with provider enabled (no config errors in logs).
  - [ ] New upload ends up as object in bucket under prefix.

  **QA scenarios**:
  ```
  Scenario: Upload writes to bucket
    Tool: Bash (kubectl) + S3 client (inside cluster)
    Steps:
      1. Upload a small image to a Matrix room (via curl client API or existing client).
      2. List objects in bucket; confirm new key under `synapse/`.
    Expected: object exists in bucket.
    Evidence: .sisyphus/evidence/task-4-s3-object-list.txt
  ```

- [ ] 5. Deploy + verify runtime (GitOps)

  **What to do**:
  - Run `make manifests` and commit changes.
  - Trigger Flux reconcile (`make reconcile` or equivalent).
  - Verify Synapse rollout + readiness.

  **Recommended Agent Profile**:
  - **Category**: quick
  - **Skills**: [kubernetes-tools, git-master]

  **Parallelization**:
  - Wave: 4
  - Blocked by: 2-4

  **Acceptance criteria**:
  - [ ] Synapse pod ready.
  - [ ] Provider import works (task 3).
  - [ ] New uploads go to S3 (task 4).

  **QA scenarios**:
  ```
  Scenario: Rollout healthy
    Tool: Bash (kubectl)
    Steps:
      1. `kubectl rollout status -n <apps-ns> deploy/synapse-matrix-synapse --timeout=5m`
      2. `kubectl logs -n <apps-ns> deploy/synapse-matrix-synapse -c synapse | grep -i s3 | head`
    Expected: rollout complete; no provider exceptions.
    Evidence: .sisyphus/evidence/task-5-rollout.txt
  ```

- [ ] 6. Migrate existing media to S3 + delete local after verify

  **What to do**:
  - Schedule downtime: scale Synapse to 0.
  - Run `s3_media_upload` workflow against the media store path + DB creds (per provider README).
    - `update <media_path> <age>` then `upload <media_path> <bucket> --delete`.
  - Bring Synapse back; verify old media loads.

  **Must NOT do**:
  - Don’t delete the PVC; keep for rollback window.

  **Recommended Agent Profile**:
  - **Category**: general
  - **Skills**: [kubernetes-tools]

  **Parallelization**:
  - Wave: 4
  - Blocked by: 5

  **References**:
  - Provider README “Regular cleanup job” section and `scripts/s3_media_upload`.

  **Acceptance criteria**:
  - [ ] Migration run logs show uploaded files and deletion.
  - [ ] At least 1 “old” media event is still retrievable after migration.

  **QA scenarios**:
  ```
  Scenario: Migrate and validate old media
    Tool: Bash (kubectl)
    Steps:
      1. `kubectl scale -n <apps-ns> deploy/synapse-matrix-synapse --replicas=0`
      2. Run migration job/pod to execute `s3_media_upload update ...` then `upload ... --delete`.
      3. `kubectl scale ... --replicas=1`
      4. Fetch a known old media URL; expect HTTP 200.
    Expected: old media served; local files removed.
    Evidence: .sisyphus/evidence/task-6-migration.txt
  ```

---

## Final Verification Wave (MANDATORY)

- [ ] F1. Plan compliance audit (oracle)
- [ ] F2. Code/config quality review (unspecified-high)
- [ ] F3. Runtime QA replay (unspecified-high)
- [ ] F4. Scope fidelity check (deep)

---

## Commit Strategy

- Commit 1: `feat(matrix): add OBC bucket for synapse media`
- Commit 2: `feat(matrix): enable synapse S3 media storage provider`

> Do not push without explicit user approval.

---

## Success Criteria

- Synapse serves new + old media after migration.
- Bucket contains expected objects under prefix.
- No secrets leaked into git.

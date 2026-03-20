# Synapse performance + media speedup (k8s)

## TL;DR
> **Summary**: Measure baseline → fix Postgres memory misconfig + raise DB/Synapse resources → verify/complete S3 media migration → add minimal metrics.
> **Deliverables**: faster Element Web navigation; faster media loads; proven S3 (Ceph RGW) media path; evidence files.
> **Effort**: Medium
> **Parallel**: YES — 3 waves + final verification
> **Critical Path**: Baseline → Postgres fix → Synapse tune → S3 verify/migrate → verify

## Context
### Original Request
- “Improve drastically performance of synapse matrix … slow navigation in element.io; media loads slow; use k8s; media from S3 (ceph object store) verify working.”

### Interview Summary
- Rollout style: **measure → tune resources first**.
- Maintenance window: **≤1h OK**.
- Client path: **LAN**.

### Repo Reality (ground truth)
- Synapse Helm release: `modules/kubenix/apps/matrix.nix`
  - Chart: ananace `matrix-synapse` **3.12.19**; image `ghcr.io/element-hq/synapse:v1.146.0`.
  - Strategy `Recreate` (RWO PVC).
  - Resources: req `100m/256Mi`, lim `300m/1Gi`.
  - External Postgres: `postgresql-18-hl:5432`, db `synapse`, user `postgres`.
  - External Redis: `redis-headless:6379`.
  - S3 provider configured via `media_storage_providers` to `kubenix.lib.objectStoreEndpoint` with `bucket=matrix-synapse-media`, `prefix=synapse/`, `store_local+store_remote`, `store_synchronous=false`.
  - OBC: `resources.objectbucketclaim."matrix-synapse-media"` with SC `rook-ceph-objectstore`.
- Object store endpoint: `modules/kubenix/_lib/default.nix` → `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local`.
- Postgres: `modules/kubenix/apps/postgresql-18.nix`
  - Container limit **1Gi**, but config sets `maintenance_work_mem = '2GB'`, `effective_cache_size='10GB'`, `work_mem='64MB'`.
- Redis: `modules/kubenix/apps/redis.nix` (standalone, PVC 8Gi, metrics disabled).
- Namespace quotas + LimitRange: `modules/kubenix/bootstrap/resource-quotas.nix` (apps has generous quotas; per-container max 2 CPU / 4Gi).
- Existing S3 migration job note: `.sisyphus/notepads/synapse-s3-media-rgw/synapse-migration-job.yaml` uses `/synapse/data/media`.

### Metis Review (gaps addressed)
- Treat Postgres memory settings as **critical bug** (must fix first).
- Assume S3 migration may be incomplete; must **verify local vs S3** before deleting local.
- Workers NOT default: prefer monolith + resources/caches first (match user preference).

## Work Objectives
### Core Objective
- Reduce /sync + timeline latency and media fetch latency by removing CPU throttling + DB OOM risk + ensuring media served from RGW (not PVC).

### Deliverables
- Evidence baseline vs after: API timing, resource usage, OOM/restarts, S3 object presence.
- Postgres settings fit container limits; Postgres has adequate CPU/mem.
- Synapse has adequate CPU/mem; caches tuned (safe).
- S3 media storage proven working; migration completed if needed; local deletion only after proof.

### Definition of Done (agent-verifiable)
- `make manifests` succeeds for each change set.
- Synapse API timing improves (LAN):
  - `/_matrix/client/versions` and a representative `/sync` request complete faster than baseline (recorded).
- No OOMKill / crashloop for Postgres/Synapse during a 30–60 min watch window.
- S3 verification:
  - bucket `matrix-synapse-media` has objects under `synapse/`.
  - new upload creates new object(s) within 60s (or documented expected async delay).

### Must NOT Have (guardrails)
- NO edits to `.k8s/*.yaml` (generated).
- NO Ceph destructive ops (finalizers, rook-ceph namespace deletions).
- NO Synapse workers unless explicitly triggered by post-tuning measurements.
- NO deleting local media until S3 upload/read proof exists.

## Verification Strategy
> Infra-style: **tests-after / none**. Verification is `make manifests` + k8s probes + timed curls + logs + object store queries.
- Evidence files: `.sisyphus/evidence/task-{N}-{slug}.txt`

## Execution Strategy
### Parallel Execution Waves
Wave 1 (baseline + proofs)
- Measure current latency/resource/OOM; prove S3 provider actually loaded; quantify local-vs-S3 media.

Wave 2 (fix DB + tune core)
- Fix Postgres memory misconfig + raise resources; raise Synapse resources + safe cache tuning.

Wave 3 (media + monitoring)
- Complete S3 migration if needed; optionally add minimal Prometheus scraping.

### Dependency Matrix (summary)
- 2 (baseline) blocks everything.
- 3 (Postgres fix) blocks 4 (Synapse tune) if Postgres is unstable/OOM.
- 5 (S3 migrate) blocked by 2 (must verify migration need) and requires Synapse scaled down (RWO).

## TODOs
> Every task includes verification + evidence output.

- [ ] 1. Baseline: capture latency + resource + restart/OOM signals

  **What to do**:
  - Capture current pod placement + restarts (Synapse, Postgres, Redis, bridges) and `kubectl top`.
  - Time key endpoints from inside cluster and from LAN client (if automation available).
  - Check events for OOMKilled and CrashLoopBackOff in `apps`.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: [`kubernetes-tools`] (cluster queries)

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 2-7 | Blocked By: none

  **References**:
  - Synapse app: `modules/kubenix/apps/matrix.nix`
  - Postgres app: `modules/kubenix/apps/postgresql-18.nix`
  - Redis app: `modules/kubenix/apps/redis.nix`

  **Acceptance Criteria**:
  - [ ] Evidence includes:
    - `kubectl get pods -n apps` (restarts)
    - `kubectl top pod -n apps` (cpu/mem)
    - events filtered for OOMKilled
    - timed curl(s) for `/_matrix/client/versions` and 1 representative `/sync`

  **QA Scenarios**:
  ```
  Scenario: Capture baseline
    Tool: Bash or kubernetes-tools
    Steps:
      1. Record restarts + resource usage for synapse/postgres/redis.
      2. Curl/timing from a pod in-cluster to Synapse service.
    Expected: baseline numbers recorded.
    Evidence: .sisyphus/evidence/task-1-baseline.txt

  Scenario: Detect OOM/restarts
    Tool: Bash or kubernetes-tools
    Steps:
      1. Query events for OOMKilled/CrashLoop in apps.
    Expected: clear YES/NO with pod names.
    Evidence: .sisyphus/evidence/task-1-oom-scan.txt
  ```

  **Commit**: NO

- [ ] 2. Prove S3 media path is active + quantify local vs S3

  **What to do**:
  - In Synapse pod: verify python can import `s3_storage_provider` and that `PYTHONPATH=/modules` is set.
  - Verify OBC/Secret exists for `matrix-synapse-media`.
  - Count local media files under `/synapse/data/media` and compare with S3 object count under `synapse/`.
  - Upload a test image via Matrix client (or API) and confirm it appears in S3 (async allowed, but must appear).

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: [`kubernetes-tools`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5 | Blocked By: 1

  **References**:
  - S3 provider config: `modules/kubenix/apps/matrix.nix` (media_storage_providers)
  - OBC definition: `modules/kubenix/apps/matrix.nix:355-364`
  - RGW endpoint: `modules/kubenix/_lib/default.nix:101`
  - Migration job pattern: `.sisyphus/notepads/synapse-s3-media-rgw/synapse-migration-job.yaml`

  **Acceptance Criteria**:
  - [ ] Evidence shows:
    - `import s3_storage_provider` succeeds
    - local media file count
    - S3 object listing/count (Prefix `synapse/`)
    - new upload produces new S3 object(s)

  **QA Scenarios**:
  ```
  Scenario: Verify provider + S3 writes
    Tool: kubernetes-tools
    Steps:
      1. Exec: print env PYTHONPATH; python -c 'import s3_storage_provider; print("OK")'.
      2. List objects in bucket (via awscli helper pod or python boto3).
      3. Upload a test media; re-list objects.
    Expected: provider OK; object count increases after upload.
    Evidence: .sisyphus/evidence/task-2-s3-proof.txt

  Scenario: Detect incomplete migration
    Tool: kubernetes-tools
    Steps:
      1. Count files under /synapse/data/media.
      2. Compare with S3 objects count.
    Expected: clear conclusion: “migration complete” or “incomplete; run job”.
    Evidence: .sisyphus/evidence/task-2-migration-gap.txt
  ```

  **Commit**: NO

- [ ] 3. Fix Postgres memory misconfig + raise Postgres resources (stability first)

  **What to do**:
  - Edit `modules/kubenix/apps/postgresql-18.nix` `primary.extendedConfiguration` to fit container memory.
  - Set exact values (decision-complete):
    - `shared_buffers = 768MB`
    - `effective_cache_size = '2304MB'`
    - `work_mem = '16MB'`
    - `maintenance_work_mem = '512MB'`
    - keep `autovacuum_*` and `log_min_duration_statement = 2000`
  - Raise Postgres container resources (decision-complete):
    - requests: cpu `250m`, memory `1Gi`
    - limits: cpu `1000m`, memory `3Gi`
  - Deploy change; verify Postgres is stable, no OOMKill.

  **Must NOT do**:
  - Don’t touch storageClass/PVC.
  - Don’t change charts/versions.

  **Recommended Agent Profile**:
  - Category: `writing`
  - Skills: [`writing-nix-code`] (safe Nix edits)

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 4-7 | Blocked By: 1

  **References**:
  - Current problematic settings: `modules/kubenix/apps/postgresql-18.nix:66-88`
  - Resource block: `modules/kubenix/apps/postgresql-18.nix:89-100`
  - Synapse Postgres tuning doc (external): https://github.com/matrix-org/synapse/blob/develop/docs/postgres.md

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds.
  - [ ] Postgres pod Running.
  - [ ] `SHOW shared_buffers; SHOW maintenance_work_mem; SHOW work_mem;` match chosen values.
  - [ ] No Postgres OOMKilled events after deploy.

  **QA Scenarios**:
  ```
  Scenario: Verify Postgres config applied
    Tool: kubernetes-tools
    Steps:
      1. Exec psql: SHOW memory settings.
    Expected: values match plan.
    Evidence: .sisyphus/evidence/task-3-postgres-show.txt

  Scenario: Verify stability
    Tool: kubernetes-tools
    Steps:
      1. Watch events for 15m; confirm no OOM/restarts.
    Expected: stable.
    Evidence: .sisyphus/evidence/task-3-postgres-stability.txt
  ```

  **Commit**: YES | Message: `fix(postgres): align memory + resources for synapse load` | Files: `modules/kubenix/apps/postgresql-18.nix`

- [ ] 4. Raise Synapse resources + safe cache tuning (no workers)

  **What to do**:
  - Edit `modules/kubenix/apps/matrix.nix`:
    - resources requests: cpu `250m`, memory `512Mi`
    - resources limits: cpu `1000m`, memory `2Gi`
    - add cache tuning under `extraConfig` (decision-complete):
      - `caches.global_factor = 1.0`
      - `event_cache_size = "20K"`
  - Keep `use_presence = false` (already).
  - Deploy; re-run baseline endpoint timings and `kubectl top`.

  **Recommended Agent Profile**:
  - Category: `writing`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 6-7 | Blocked By: 3

  **References**:
  - Synapse values: `modules/kubenix/apps/matrix.nix` (resources at ~336-346; extraConfig at ~209+)
  - Synapse perf guide (external): https://matrix-org.github.io/synapse/latest/usage/administration/understanding_synapse_through_grafana_graphs.html

  **Acceptance Criteria**:
  - [ ] `make manifests` succeeds.
  - [ ] Synapse pod Running.
  - [ ] `/_matrix/client/versions` timing improved vs Task 1 baseline (record numbers).
  - [ ] No Synapse OOMKilled events after deploy.

  **QA Scenarios**:
  ```
  Scenario: Verify latency improvement
    Tool: kubernetes-tools
    Steps:
      1. Run same timed curl(s) as baseline.
    Expected: lower time_total than baseline (recorded).
    Evidence: .sisyphus/evidence/task-4-latency.txt

  Scenario: Verify no throttling regression
    Tool: kubernetes-tools
    Steps:
      1. Record kubectl top for synapse during active use window.
    Expected: cpu not pinned at limit; mem < limit.
    Evidence: .sisyphus/evidence/task-4-top.txt
  ```

  **Commit**: YES | Message: `perf(synapse): raise resources + tune caches` | Files: `modules/kubenix/apps/matrix.nix`

- [ ] 5. If needed: complete S3 media migration (safe, reversible)

  **Trigger**: Task 2 shows local media count >> S3 object count OR old media fetch is slow and local-only.

  **What to do**:
  - Ensure Synapse scaled down/stopped (RWO PVC) before running migration job.
  - Run migration job equivalent to `.sisyphus/notepads/synapse-s3-media-rgw/synapse-migration-job.yaml` (recommended: encode as kubenix Job for repeatability).
  - Commands must match (decision-complete):
    - `python -m s3_storage_provider.s3_media_upload update /synapse/data/media 0`
    - `python -m s3_storage_provider.s3_media_upload upload /synapse/data/media matrix-synapse-media --delete`
  - After job: verify S3 object count increased; verify a known old MXC is readable.
  - Do NOT delete PVC; keep as rollback window.

  **Must NOT do**:
  - Don’t delete local before verifying reads from S3.
  - Don’t run concurrently with Synapse (PVC conflict).

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: [`kubernetes-tools`, `writing-nix-code`]

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 6-7 | Blocked By: 2,4

  **References**:
  - Job template: `.sisyphus/notepads/synapse-s3-media-rgw/synapse-migration-job.yaml`
  - Media path rule (repo lesson): `.docs/rules.md` (“Synapse media path is /synapse/data/media”)
  - Provider repo: https://github.com/matrix-org/synapse-s3-storage-provider

  **Acceptance Criteria**:
  - [ ] Migration job completes successfully.
  - [ ] S3 object count under `synapse/` increased.
  - [ ] Local file count reduced (if `--delete` used) AND old media fetch works.

  **QA Scenarios**:
  ```
  Scenario: Run migration job
    Tool: kubernetes-tools
    Steps:
      1. Scale down synapse; run job; wait completion.
    Expected: job Succeeded.
    Evidence: .sisyphus/evidence/task-5-job.txt

  Scenario: Verify old media served
    Tool: Bash or kubernetes-tools
    Steps:
      1. Fetch 1 known old MXC via /_matrix/media/... endpoint.
    Expected: HTTP 200, reasonable time.
    Evidence: .sisyphus/evidence/task-5-old-media.txt
  ```

  **Commit**: YES/NO (depends if job encoded in repo) | Message: `chore(synapse): add one-off media migration job` | Files: new kubenix job file if created

- [ ] 6. Optional: tighten S3 correctness (only after migration complete)

  **Trigger**: Task 2/5 confirms S3 writes/reads are reliable.

  **What to do**:
  - Consider switching `store_synchronous = true` to eliminate “async lag” for new uploads.
  - Keep checksum settings as `when_required` (RGW compatibility).

  **Recommended Agent Profile**:
  - Category: `writing`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 7 | Blocked By: 5

  **References**:
  - `modules/kubenix/apps/matrix.nix:217-232`
  - Provider repo README: https://github.com/matrix-org/synapse-s3-storage-provider/blob/master/README.md

  **Acceptance Criteria**:
  - [ ] New upload appears in S3 within 10s (measured) AND is readable.

  **QA Scenarios**:
  ```
  Scenario: Validate synchronous writes
    Tool: kubernetes-tools
    Steps:
      1. Upload a test media; immediately list S3 objects; fetch via /_matrix/media.
    Expected: object exists immediately; fetch 200.
    Evidence: .sisyphus/evidence/task-6-sync.txt
  ```

  **Commit**: YES | Message: `feat(synapse): enable synchronous S3 media writes` | Files: `modules/kubenix/apps/matrix.nix`

- [ ] 7. Optional: add minimal metrics for “measure-first” loop

  **What to do**:
  - Expose Synapse Prometheus metrics (Synapse supports it; chart may have value key).
  - Enable Redis metrics (chart supports; currently disabled).
  - Add ServiceMonitor(s) (Prometheus operator exists).

  **Recommended Agent Profile**:
  - Category: `deep`
  - Skills: [`kubernetes-tools`, `writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: Final verification | Blocked By: 4

  **References**:
  - Prom stack: `modules/kubenix/monitoring/kube-prometheus-stack.nix`
  - ServiceMonitor CRD presence: `modules/kubenix/_crds.nix`

  **Acceptance Criteria**:
  - [ ] Prometheus targets show Synapse + Redis metrics endpoints `UP`.
  - [ ] Evidence includes target scrape success.

  **QA Scenarios**:
  ```
  Scenario: Verify scrape targets
    Tool: kubernetes-tools
    Steps:
      1. Query ServiceMonitor/targets; confirm UP.
    Expected: synapse + redis targets UP.
    Evidence: .sisyphus/evidence/task-7-metrics.txt
  ```

  **Commit**: YES | Message: `feat(monitoring): add synapse+redis metrics scraping` | Files: monitoring + app nix files

## Final Verification Wave (MANDATORY)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA (Element LAN) — unspecified-high
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Prefer 2–4 commits (Postgres fix, Synapse tune, optional migration job, optional monitoring).
- Never commit secrets; only references.

## Success Criteria
- Measured improvement vs baseline for:
  - /_matrix/client/versions latency
  - representative /sync latency
  - media fetch latency for a known MXC
- No Postgres/Synapse OOMKills.
- S3 media proven working and migration either complete or explicitly not needed.

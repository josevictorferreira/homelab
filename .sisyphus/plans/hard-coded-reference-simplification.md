# Hard-coded Reference Simplification

## TL;DR
> **Summary**: Remove repeated behavior-preserving reference literals by centralizing shared kubenix defaults and shared-storage names, then replace consumers without changing rendered manifests.
> **Deliverables**:
> - Shared kubenix reference constants API
> - Repo-wide consumer replacement for in-scope literals
> - Validation proof via existing repo checks and zero-behavior manifest diff
> **Effort**: Medium
> **Parallel**: YES - 3 waves
> **Critical Path**: 1 → 2 → 3/4/5 → 6 → F1-F4

## Context
### Original Request
Find repeated hard-coded values/variables across the repo and simplify them into cleaner shared references, using `modules/kubenix/apps/immich.nix` and `immichLibraryPVC = "cephfs-shared-storage-root"` as the example pattern.

### Interview Summary
- Scope: whole repo
- Change policy: behavior-preserving only
- Verification: existing repo checks only
- Quality bar: clean, simple, elegant, maintainable

### Metis Review (gaps addressed)
- Constrain scope to shared reference literals only
- Do not touch service-specific names, ports, image tags, digests, secrets, or behavioral chart wiring
- Prefer `kubenix.lib.*` constants and existing `homelab.kubernetes.*` attrs over cross-file state
- Because kubenix files are evaluated independently, shared values must live in `_lib/default.nix` or central config, not implicit module linkage

## Work Objectives
### Core Objective
Create one clean shared-reference layer for repeated kubenix/Nix literals already acting as global defaults or shared resource names, then migrate consumers with zero intended behavior change.

### Deliverables
- New shared constants in `modules/kubenix/_lib/default.nix`
- Consumer migrations for in-scope literals
- One audited inventory of all changed literal categories and exclusions
- Validation artifacts proving no rendered-manifest drift

### Definition of Done (verifiable conditions with commands)
- `make manifests` succeeds
- `make check` succeeds
- `make lint` succeeds
- Rendered manifests are unchanged vs baseline except for expected non-semantic formatting noise; target is zero diff
- In-scope hard-coded literals no longer appear in consumer files

### Must Have
- Central constants for shared storage class, ingress class, TLS secret, cluster issuer, and shared-storage PVC names
- Consumer replacements use `kubenix.lib.*` or `homelab.kubernetes.*`
- Explicit exclusion handling for literals that are authoritative resource definitions rather than repeated references

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No behavior change
- No migration of hand-rolled ingress blocks to different helper shapes unless value substitution only
- No edits to `.k8s/` generated files
- No secret changes
- No edits to image tags, versions, ports, service-specific generated names, resource requests/limits, or IP allocations
- Do not replace authoritative resource names like CephBlockPool names or cert-manager certificate secret definitions when they are source-of-truth, not repeated consumer refs

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after + existing repo commands (`make manifests`, `make check`, `make lint`)
- QA policy: Every task includes executable verification and evidence capture
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: baseline + inventory + shared API design
Wave 2: consumer migrations by literal category in parallel
Wave 3: outlier cleanup + final sweep

### Dependency Matrix (full, all tasks)
| Task | Blocks | Blocked By |
|---|---|---|
| 1 | 2,3,4,5,6 | - |
| 2 | 3,4,5,6 | 1 |
| 3 | 6 | 1,2 |
| 4 | 6 | 1,2 |
| 5 | 6 | 1,2 |
| 6 | F1,F2,F3,F4 | 2,3,4,5 |
| F1 | - | 6 |
| F2 | - | 6 |
| F3 | - | 6 |
| F4 | - | 6 |

### Agent Dispatch Summary
| Wave | Tasks | Categories |
|---|---:|---|
| 1 | 2 | business-logic, quick |
| 2 | 3 | quick, unspecified-low |
| 3 | 1 | quick |
| Final | 4 | oracle, unspecified-high, deep |

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Capture baseline and classify literals

  **What to do**: Run the current validation baseline, render manifests, snapshot `.k8s` as comparison baseline, and produce a checked inventory of in-scope literal categories to refactor. Limit inventory to shared reference literals only: default storage class, ingress class, TLS secret, cluster issuer, shared-storage PVC names, and any direct namespace outlier equivalent to `"apps"`. Record explicit exclusions discovered during the scan.
  **Must NOT do**: Do not edit source yet. Do not classify service-specific names, ports, image tags, digests, IPs, resource limits, or secret keys as in-scope.

  **Recommended Agent Profile**:
  - Category: `business-logic` - Reason: needs disciplined classification and scope enforcement
  - Skills: `[]` - no extra skill needed
  - Omitted: [`writing-nix-code`] - task is inventory/verification, not implementation

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,5,6] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `modules/kubenix/apps/immich.nix:3-7` - example of local literal alias pointing at shared PVC name
  - Pattern: `modules/kubenix/_lib/default.nix:6-102` - current shared helper surface; extend here instead of inventing a new location
  - Pattern: `config/kubernetes.nix:78-84` - canonical namespace source
  - Pattern: `modules/kubenix/default.nix:48-58` - kubenix files are evaluated independently; shared state must come from `kubenix.lib` or `homelab`
  - Command Source: `Makefile:10-56` - repo-native validation commands

  **Acceptance Criteria** (agent-executable only):
  - [ ] Baseline evidence captures successful `make manifests`, `make check`, and `make lint`
  - [ ] Baseline copy of `.k8s` exists for later diff comparison
  - [ ] Inventory file/evidence lists every in-scope literal category and every explicit exclusion category

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline validation succeeds
    Tool: Bash
    Steps: Run `make manifests`, `make check`, and `make lint`; copy `.k8s` to a baseline snapshot path; write outputs to evidence files.
    Expected: All commands exit 0 and baseline snapshot exists.
    Evidence: .sisyphus/evidence/task-1-baseline.txt

  Scenario: Scope filter rejects out-of-scope literals
    Tool: Bash
    Steps: Search candidate literals found during inventory and classify at least one service-specific literal and one authoritative resource-definition literal as excluded.
    Expected: Evidence shows excluded examples such as service-specific generated names or certificate source-of-truth names.
    Evidence: .sisyphus/evidence/task-1-scope-filter.txt
  ```

  **Commit**: NO | Message: `refactor(kubenix): baseline literal inventory` | Files: []

- [x] 2. Add canonical shared-reference constants API

  **What to do**: Extend `modules/kubenix/_lib/default.nix` with simple shared constants in the existing `rec` attrset. Required names: `defaultStorageClass`, `defaultIngressClass`, `defaultTLSSecret`, `defaultClusterIssuer`, and a shared-storage attrset like `sharedStorage = { rootPVC = "..."; downloadsPVC = "..."; };`. Reuse existing helper patterns; do not create a new module or nested architecture.
  **Must NOT do**: Do not change function signatures. Do not move helpers to another file. Do not introduce derived behavior or implicit cross-module loading.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: single-file foundational refactor with low algorithmic complexity
  - Skills: [`writing-nix-code`] - ensure idiomatic Nix constants shape
  - Omitted: [`creating-nix-modules`] - no new module is needed

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,5,6] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `modules/kubenix/_lib/default.nix:6-102` - place new constants beside existing helpers like `objectStoreEndpoint`
  - Pattern: `config/kubernetes.nix:78-84` - namespaces already centralized there; do not duplicate that pattern in `_lib`
  - Pattern: `modules/kubenix/storage/shared-storage-pvc.nix:3-8` - existing naming style for storage identifiers; keep naming obvious and explicit

  **Acceptance Criteria** (agent-executable only):
  - [ ] `_lib/default.nix` exposes the five required shared-reference entries
  - [ ] `make check` passes after adding constants with no consumer changes
  - [ ] `make manifests` output diff vs baseline is empty after this task

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Constants compile without consumer adoption
    Tool: Bash
    Steps: Edit `_lib/default.nix`; run `git add modules/kubenix/_lib/default.nix`; run `make check` and `make manifests`; diff current `.k8s` against baseline.
    Expected: Commands exit 0 and diff is empty.
    Evidence: .sisyphus/evidence/task-2-lib-constants.txt

  Scenario: No accidental helper API drift
    Tool: Bash
    Steps: Inspect diff for `_lib/default.nix` and confirm only new constant attrs were added; no existing helper signature or body changed except optional self-reference to new constants.
    Expected: Diff shows additive constants and any literal-to-constant substitution only.
    Evidence: .sisyphus/evidence/task-2-api-guard.txt
  ```

  **Commit**: YES | Message: `refactor(kubenix): add shared reference constants` | Files: [`modules/kubenix/_lib/default.nix`]

- [x] 3. Replace storage-class literals with canonical reference

  **What to do**: Replace in-scope consumer uses of the repeated default storage class literal with `kubenix.lib.defaultStorageClass`. Cover both raw Kubernetes fields (`storageClassName`) and Helm values (`storageClass`) but keep the original field names unchanged. Include `_submodules/release.nix` if it currently carries the same default.
  **Must NOT do**: Do not replace authoritative resource names that merely equal the same string but mean something different. Do not rename fields. Do not change size, access mode, or reclaim behavior.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: repetitive literal replacement with strong guardrails
  - Skills: [`writing-nix-code`] - preserve Nix style while editing many consumers
  - Omitted: [`nix-refactor`] - scope is narrow and explicit

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `modules/kubenix/apps/immich.nix:70-76` - Helm value uses `storageClass`
  - Pattern: `modules/kubenix/_lib/default.nix:6-102` - canonical constant source added in Task 2
  - Pattern: `modules/kubenix/storage/shared-storage-pvc.nix:42-47` - raw PV/PVC files use `storageClassName`; preserve field naming semantics
  - Pattern: `Makefile:25-26` - `make manifests` is the semantic regression gate

  **Acceptance Criteria** (agent-executable only):
  - [ ] All in-scope repeated default-storage-class consumers reference `kubenix.lib.defaultStorageClass`
  - [ ] No field-name drift from `storageClass` to `storageClassName` or vice versa
  - [ ] `make manifests`, `make check`, and `make lint` pass
  - [ ] Manifest diff vs baseline is empty

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Consumer replacement preserves manifests
    Tool: Bash
    Steps: Replace storage-class consumers; run `git add -A`; run `make manifests`; diff `.k8s` against baseline; run `make check` and `make lint`.
    Expected: All commands pass and diff is empty.
    Evidence: .sisyphus/evidence/task-3-storage-class.txt

  Scenario: Authoritative same-string resources stay untouched
    Tool: Bash
    Steps: Search for remaining occurrences of the original storage-class literal and inspect excluded matches.
    Expected: Remaining matches are only approved exclusions, documented in evidence.
    Evidence: .sisyphus/evidence/task-3-storage-class-exclusions.txt
  ```

  **Commit**: YES | Message: `refactor(kubenix): centralize default storage class refs` | Files: [`modules/kubenix/**/*.nix`, `modules/kubenix/_submodules/release.nix`]

- [x] 4. Replace ingress-class, TLS-secret, and issuer literals with canonical references

  **What to do**: Replace repeated consumer literals for ingress class, wildcard TLS secret, and cluster issuer with `kubenix.lib.defaultIngressClass`, `kubenix.lib.defaultTLSSecret`, and `kubenix.lib.defaultClusterIssuer`. Apply only literal substitutions inside existing structures. Include `_submodules/release.nix` and any hand-rolled ingress blocks that already follow current shape.
  **Must NOT do**: Do not migrate consumers from manual ingress structures to `kubenix.lib.ingressFor`/`ingressDomainFor`. Do not change host/path/service wiring. Do not touch authoritative source-of-truth definitions such as cert-manager certificate specs that intentionally create the TLS secret.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: constrained repeated substitutions across known patterns
  - Skills: [`writing-nix-code`] - preserve consistent Nix formatting in multi-file edits
  - Omitted: [`frontend-ui-ux`] - irrelevant to infrastructure refactor

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `modules/kubenix/_lib/default.nix:28-99` - ingress helpers already embed these defaults; switch them to constant-backed references too
  - Pattern: `modules/kubenix/apps/immich.nix:105-125` - representative hand-rolled ingress block with class and TLS secret
  - Pattern: `config/kubernetes.nix` - do not move these values here; they belong with kubenix ingress defaults, not cluster topology
  - Pattern: `Makefile:25-26` - manifest regen is the semantic correctness check

  **Acceptance Criteria** (agent-executable only):
  - [ ] All in-scope repeated ingress-class, TLS-secret, and issuer consumer literals reference shared constants
  - [ ] Hand-rolled ingress structures remain structurally identical except literal substitution
  - [ ] `make manifests`, `make check`, and `make lint` pass
  - [ ] Manifest diff vs baseline is empty

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Ingress-related literal replacement is behavior-neutral
    Tool: Bash
    Steps: Replace in-scope ingress-class/TLS/issuer literals; run `git add -A`; run `make manifests`; diff `.k8s` against baseline; run `make check` and `make lint`.
    Expected: All commands pass and diff is empty.
    Evidence: .sisyphus/evidence/task-4-ingress-defaults.txt

  Scenario: Source-of-truth definitions remain excluded
    Tool: Bash
    Steps: Search remaining raw literal occurrences and inspect cert-manager or equivalent source-of-truth resources.
    Expected: Remaining matches are documented approved exclusions only.
    Evidence: .sisyphus/evidence/task-4-ingress-exclusions.txt
  ```

  **Commit**: YES | Message: `refactor(kubenix): centralize ingress default refs` | Files: [`modules/kubenix/**/*.nix`, `modules/kubenix/_submodules/release.nix`]

- [x] 5. Replace shared-storage PVC name literals with canonical references

  **What to do**: Replace consumer references to shared-storage PVC names with `kubenix.lib.sharedStorage.rootPVC` and `kubenix.lib.sharedStorage.downloadsPVC` (or exact names from Task 2 if refined there). Apply this to all in-scope consumers across apps/backup areas. Keep authoritative PVC/PV definition files as the source of literal values if they define the resource names directly.
  **Must NOT do**: Do not alter PVC definitions themselves unless needed only to self-reference the new constant in the defining file. Do not confuse `cephfs-shared-storage` with `cephfs-shared-storage-root` if both exist. Do not change namespaces or mount semantics.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: explicit cross-file consumer replacement with high naming-risk but low logic complexity
  - Skills: [`writing-nix-code`] - maintain readable naming and attr access
  - Omitted: [`developing-containers`] - irrelevant

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `modules/kubenix/apps/immich.nix:3-7,35-37` - user-provided example of local alias wrapping a repeated PVC name
  - Pattern: `modules/kubenix/storage/shared-storage-pvc.nix:3-8,37-48` - representative PVC definition file; treat definition-vs-consumer carefully
  - Pattern: `modules/kubenix/default.nix:48-58` - no cross-file state; shared constants must be imported through `kubenix.lib`

  **Acceptance Criteria** (agent-executable only):
  - [ ] All in-scope shared-storage PVC consumer references use canonical shared constants
  - [ ] Any remaining raw PVC-name literal occurrences are documented approved definition-side exclusions only
  - [ ] `make manifests`, `make check`, and `make lint` pass
  - [ ] Manifest diff vs baseline is empty

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Shared PVC consumers now use canonical refs
    Tool: Bash
    Steps: Replace in-scope shared PVC name consumers; run `git add -A`; run `make manifests`; diff `.k8s` against baseline; run `make check` and `make lint`.
    Expected: All commands pass and diff is empty.
    Evidence: .sisyphus/evidence/task-5-shared-pvc-refs.txt

  Scenario: Similar-but-different PVC names are not collapsed incorrectly
    Tool: Bash
    Steps: Inspect remaining PVC-name matches after replacement and compare against definition files.
    Expected: Evidence distinguishes true shared names from similarly named but different resources.
    Evidence: .sisyphus/evidence/task-5-pvc-exclusions.txt
  ```

  **Commit**: YES | Message: `refactor(kubenix): centralize shared pvc references` | Files: [`modules/kubenix/apps/*.nix`, `modules/kubenix/backup/*.nix`, `modules/kubenix/storage/*.nix`]

- [x] 6. Clean outliers, run final literal sweep, and prove zero behavior drift

  **What to do**: Fix remaining approved outliers such as direct namespace string usage when an existing canonical config attr already exists. Then run the final repo sweep for all in-scope categories, regenerate manifests, compare against baseline, and store consolidated evidence. If any in-scope raw literal remains, either replace it now or classify it explicitly as an approved exclusion in evidence.
  **Must NOT do**: Do not broaden scope to unrelated literals just because they are repeated. Do not “clean up” service names or chart-specific generated resource names. Do not proceed if manifest diff shows unexplained changes.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: final pass and limited outlier cleanup
  - Skills: [`writing-nix-code`] - small Nix edits plus consistency sweep
  - Omitted: [`auditing-security`] - not a security task

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [F1,F2,F3,F4] | Blocked By: [2,3,4,5]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `config/kubernetes.nix:78-84` - canonical namespace source for namespace outliers
  - Pattern: `Makefile:10-56` - final validation command set
  - Pattern: `modules/kubenix/_lib/default.nix:6-102` - final shared API surface must remain minimal and coherent

  **Acceptance Criteria** (agent-executable only):
  - [ ] Namespace outliers and other approved final in-scope outliers are eliminated
  - [ ] Final searches for each in-scope literal category return only approved exclusions
  - [ ] `make manifests`, `make check`, and `make lint` pass
  - [ ] Final manifest diff vs baseline is empty
  - [ ] Consolidated evidence file explains any remaining approved exclusions

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Final sweep confirms no in-scope consumer literals remain
    Tool: Bash
    Steps: Run final searches for storage class, ingress class, TLS secret, issuer, shared PVC names, and namespace outliers; write results to evidence.
    Expected: Only approved exclusions remain.
    Evidence: .sisyphus/evidence/task-6-final-sweep.txt

  Scenario: Full repo validation proves behavior preservation
    Tool: Bash
    Steps: Run `make manifests`, diff `.k8s` against baseline, then run `make check` and `make lint`.
    Expected: All commands pass and diff is empty.
    Evidence: .sisyphus/evidence/task-6-validation.txt
  ```

  **Commit**: YES | Message: `refactor(kubenix): remove remaining hardcoded shared refs` | Files: [`modules/kubenix/**/*.nix`, `config/kubernetes.nix` only if needed for outlier consumption, not new defaults]

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check — deep
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: add shared kubenix constants only
- Commit 2: replace storage-class consumers
- Commit 3: replace ingress/TLS/issuer consumers
- Commit 4: replace shared-storage PVC references and outlier namespace cleanup
- Final: only if repo state and user request explicitly allow commit creation

## Success Criteria
- Shared reference API exists in one canonical place
- All in-scope consumers use shared references
- Repo validation passes
- Manifest output remains behavior-equivalent, target zero diff

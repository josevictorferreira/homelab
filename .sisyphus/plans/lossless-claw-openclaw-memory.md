# Lossless-Claw main memory for OpenClaw

## TL;DR
> **Summary**: Add `@martian-engineering/lossless-claw` to `openclaw-nix`, wire it as the OpenClaw `contextEngine`, and patch the live CephFS config idempotently so existing runtime config adopts it without a risky full secret-flow rewrite.
> **Deliverables**:
> - Nix-packaged `lossless-claw` deps + bundled plugin runtime in `openclaw-nix`
> - Kubenix fallback config enabling `lossless-claw` with persistent SQLite on CephFS
> - Startup patch logic that upgrades existing `~/Homelab/openclaw/openclaw.json` non-secret plugin fields in place
> - Build/manifests/podman verification evidence
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: T1 → T2 → T4 → T5

## Context
### Original Request
- Add `Martian-Engineering/lossless-claw` to OpenClaw as the main memory tool/plugin.
- Read upstream repo first.
- Real runtime config is `~/Homelab/openclaw/openclaw.json` on CephFS.
- Keep repo fallback config mirrored.
- No hardcoded secrets in Nix path or generated YAML.
- `openclaw-nix` container likely needs changes.

### Interview Summary
- Migration/backfill: include only if low-risk; else skip and document follow-up.
- Rollout: near-zero-downtime.
- Validation: tests-after.
- Default applied: keep `memory-core` in `plugins.slots.memory`; add `lossless-claw` in `plugins.slots.contextEngine`.
- Default applied: no full secret-sanitization refactor in this work; only add non-secret plugin bootstrap/migration.

### Metis Review (gaps addressed)
- Corrected slot mapping: upstream `lossless-claw` is a `contextEngine`, not a `memory` slot replacement.
- Keep scope tight: do **not** rewrite the existing secret-substitution architecture.
- Existing CephFS mount already gives persistent SQLite at `/home/node/.openclaw/lcm.db`; no new PVC needed.
- Live CephFS config diverges from fallback template, so implementation must patch existing config idempotently; template-only changes are insufficient.
- Avoid runtime npm install for this plugin; follow the repo’s prebuilt dependency pattern.

## Work Objectives
### Core Objective
Ship repo changes that make `openclaw-nix` capable of running `lossless-claw` as the primary context engine, with repo fallback config and live CephFS config aligned enough for safe rollout.

### Deliverables
- `oci-images/openclaw-nix/lossless-claw-deps.nix`
- `oci-images/openclaw-nix/lossless-claw-package-lock.json`
- updated `oci-images/openclaw-nix/default.nix`
- updated `modules/kubenix/apps/openclaw-config.enc.nix`
- updated `modules/kubenix/apps/openclaw-nix.nix`
- verification evidence under `.sisyphus/evidence/`

### Definition of Done (verifiable conditions with commands)
- `nix build .#openclaw-nix-image` succeeds.
- `podman load < $(nix build .#openclaw-nix-image --print-out-paths --no-link)` loads image and plugin files exist under `/lib/openclaw/dist/extensions/lossless-claw/`.
- `make manifests` succeeds.
- `sops -d .k8s/apps/openclaw-config.enc.yaml` shows `lossless-claw` in `plugins.allow`, `plugins.slots.contextEngine`, and `plugins.entries.lossless-claw.config.dbPath`.
- generated app manifest contains startup logic that patches live `openclaw.json` idempotently with `jq`.

### Must Have
- Build-time bundling of `lossless-claw`; no runtime install from npm registry.
- `plugins.slots.contextEngine = "lossless-claw"`.
- Keep `plugins.slots.memory = "memory-core"` unless implementation evidence proves incompatibility.
- Persistent DB path set to `/home/node/.openclaw/lcm.db`.
- Existing CephFS live config auto-upgraded for non-secret plugin fields.
- No new secret keys introduced unless upstream config proves mandatory.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- Do not edit `.k8s/*.yaml` directly.
- Do not hardcode secrets or placeholders like `REPLACE_ME`.
- Do not replace or remove current `memory-core` slot wiring in this work.
- Do not refactor the existing env-substitution secret flow beyond what is needed to patch non-secret plugin fields.
- Do not add migration/backfill for old memory/history unless it is trivial; default is no migration.
- Do not touch Ceph/CephFS infra, PVC definitions, or unrelated OpenClaw plugins.

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after + repo build/manifests/podman/manifest inspection.
- QA policy: Every task has agent-executed scenarios.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.

Wave 1: dependency packaging + fallback config wiring + rollout command/version alignment
Wave 2: image bundling + live-config patching + end-to-end verification

### Dependency Matrix (full, all tasks)
| Task | Depends on | Blocks |
|---|---|---|
| T1 | - | T2, T5 |
| T2 | T1 | T5 |
| T3 | - | T4, T5 |
| T4 | T3 | T5 |
| T5 | T1, T2, T3, T4 | F1-F4 |

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 3 tasks → `quick`, `writing`, `business-logic`
- Wave 2 → 2 tasks → `quick`, `general`
- Final → 4 review tasks in parallel

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Package `lossless-claw` deps as pinned Nix FOD

  **What to do**: create `oci-images/openclaw-nix/lossless-claw-deps.nix` and `oci-images/openclaw-nix/lossless-claw-package-lock.json` following `matrix-deps.nix` pattern; pin `@martian-engineering/lossless-claw` to one exact version; vendor only runtime deps needed by the plugin (`@mariozechner/pi-agent-core`, `@mariozechner/pi-ai`, `@sinclair/typebox` plus transitive lockfile state); expose an attr returning a prepared `node_modules` tree ready to copy into the plugin dir.
  **Must NOT do**: no runtime npm install fallback; no unpinned semver ranges; no edits outside `oci-images/openclaw-nix/` for this task.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: small, file-local Nix packaging task.
  - Skills: [`writing-nix-code`] — Nix derivation + lockfile packaging.
  - Omitted: [`developing-containers`] — image wiring is next task, not this one.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T2, T5 | Blocked By: none

  **References**:
  - Pattern: `oci-images/openclaw-nix/matrix-deps.nix` — existing npm FOD pattern to mirror.
  - Pattern: `oci-images/openclaw-nix/default.nix:252-270` — current node_modules copy flow for a plugin.
  - External: `https://github.com/Martian-Engineering/lossless-claw` — upstream package/plugin source.
  - External: `https://github.com/Martian-Engineering/lossless-claw/blob/main/package.json` — exact runtime deps to pin.

  **Acceptance Criteria**:
  - [ ] `oci-images/openclaw-nix/lossless-claw-deps.nix` exists and follows the repo’s prebuilt npm-deps style.
  - [ ] lockfile/file pins one exact `lossless-claw` version.
  - [ ] dependency derivation outputs a `node_modules` tree suitable for copying into the plugin dir.

  **QA Scenarios**:
  ```
  Scenario: Dependency derivation builds
    Tool: Bash
    Steps: nix build .#openclaw-nix-image |& tee .sisyphus/evidence/task-1-lossless-claw-deps-build.txt
    Expected: build reaches image eval/build with no missing lossless-claw dependency errors
    Evidence: .sisyphus/evidence/task-1-lossless-claw-deps-build.txt

  Scenario: Lockfile pins exact plugin version
    Tool: Bash
    Steps: grep -n '@martian-engineering/lossless-claw' oci-images/openclaw-nix/lossless-claw-package-lock.json | tee .sisyphus/evidence/task-1-lossless-claw-version.txt
    Expected: exactly one pinned version string present, no range-only entry
    Evidence: .sisyphus/evidence/task-1-lossless-claw-version.txt
  ```

  **Commit**: YES | Message: `feat(openclaw-nix): package lossless-claw deps` | Files: `oci-images/openclaw-nix/lossless-claw-deps.nix`, `oci-images/openclaw-nix/lossless-claw-package-lock.json`

- [x] 2. Bundle `lossless-claw` into `openclaw-nix` image rootfs

  **What to do**: update `oci-images/openclaw-nix/default.nix` to import the new deps derivation; copy the upstream `lossless-claw` plugin artifacts into both `extensions/` and `dist/extensions/` in the same way current plugins are synced; inject the vendored `node_modules` tree into the bundled plugin dir; keep the existing `openclaw` self-symlink behavior so peer dep resolution works; do **not** special-case-skip this plugin the way `memory-lancedb` is skipped.
  **Must NOT do**: do not change base entrypoint contract; do not remove matrix/whatsapp behavior; do not alter other plugin slots/config in this task.

  **Recommended Agent Profile**:
  - Category: `general` — Reason: image assembly + runtime path wiring.
  - Skills: [`writing-nix-code`,`developing-containers`] — Nix image mutation + container verification.
  - Omitted: [`managing-flakes`] — no flake/input changes needed.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T5 | Blocked By: T1

  **References**:
  - Pattern: `oci-images/openclaw-nix/default.nix:174-270` — rootfs assembly + extension copy loop.
  - Pattern: `oci-images/openclaw-nix/default.nix:266-270` — peer import resolution via `node_modules/openclaw` symlink.
  - Pattern: `oci-images/openclaw-nix/default.nix:273-337` — image build + env defaults.
  - Test: `oci-images/openclaw-nix/RUNBOOK.md:5-114` — local Podman smoke flow.
  - External: `https://github.com/Martian-Engineering/lossless-claw/blob/main/openclaw.plugin.json` — plugin id + slot contract.

  **Acceptance Criteria**:
  - [ ] built image contains `/lib/openclaw/dist/extensions/lossless-claw/openclaw.plugin.json`.
  - [ ] built image contains plugin `node_modules` for lossless-claw.
  - [ ] plugin manifest parses successfully inside the container.

  **QA Scenarios**:
  ```
  Scenario: Built image contains bundled lossless-claw plugin
    Tool: Bash
    Steps: nix build .#openclaw-nix-image --print-out-paths --no-link > .sisyphus/evidence/task-2-image-path.txt && "$(cat .sisyphus/evidence/task-2-image-path.txt)" | podman load && podman run --rm --entrypoint '' localhost/openclaw-nix:v2026.4.2 ls -la /lib/openclaw/dist/extensions/lossless-claw/ | tee .sisyphus/evidence/task-2-lossless-claw-files.txt
    Expected: directory lists `openclaw.plugin.json`, `package.json`, `src`, and `node_modules`
    Evidence: .sisyphus/evidence/task-2-lossless-claw-files.txt

  Scenario: Plugin manifest is valid JSON and id matches
    Tool: Bash
    Steps: podman run --rm --entrypoint '' localhost/openclaw-nix:v2026.4.2 node -e "const f='/lib/openclaw/dist/extensions/lossless-claw/openclaw.plugin.json'; const j=JSON.parse(require('fs').readFileSync(f,'utf8')); console.log(j.id,j.slots||j.slot||'');" | tee .sisyphus/evidence/task-2-lossless-claw-manifest.txt
    Expected: output contains `lossless-claw` and `contextEngine`
    Evidence: .sisyphus/evidence/task-2-lossless-claw-manifest.txt
  ```

  **Commit**: YES | Message: `feat(openclaw-nix): bundle lossless-claw plugin` | Files: `oci-images/openclaw-nix/default.nix`

- [x] 3. Update repo fallback config to enable `lossless-claw`

  **What to do**: edit `modules/kubenix/apps/openclaw-config.enc.nix` so fallback `configData` adds `lossless-claw` to `plugins.allow`, keeps `plugins.slots.memory = "memory-core"`, adds `plugins.slots.contextEngine = "lossless-claw"`, and defines `plugins.entries.lossless-claw = { enabled = true; config = { dbPath = "/home/node/.openclaw/lcm.db"; }; }`; keep optional LCM tuning unset unless upstream docs make one field mandatory; do not add new secret env vars unless proven required.
  **Must NOT do**: do not remove builtin memory stanza in this task; do not inject plaintext credentials; do not touch `oci-images/openclaw-nix/config.nix`.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: localized Nix config mutation.
  - Skills: [`writing-nix-code`] — kubenix config data edits.
  - Omitted: [`developing-containers`] — no image work here.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T4, T5 | Blocked By: none

  **References**:
  - Pattern: `modules/kubenix/apps/openclaw-config.enc.nix:566-595` — current memory/plugins fallback config.
  - Pattern: `modules/kubenix/apps/openclaw-config.enc.nix:600-633` — secret/configmap split.
  - Runtime truth: `/home/josevictor/Homelab/openclaw/openclaw.json:632-680` — current live plugin layout that needs alignment.
  - External: `https://github.com/Martian-Engineering/lossless-claw` — upstream config docs.

  **Acceptance Criteria**:
  - [ ] fallback config renders `lossless-claw` in `plugins.allow`.
  - [ ] fallback config renders `plugins.slots.contextEngine = "lossless-claw"`.
  - [ ] fallback config renders `dbPath = "/home/node/.openclaw/lcm.db"`.

  **QA Scenarios**:
  ```
  Scenario: Rendered fallback config contains lossless-claw wiring
    Tool: Bash
    Steps: make manifests |& tee .sisyphus/evidence/task-3-make-manifests.txt && sops -d .k8s/apps/openclaw-config.enc.yaml | grep -n 'lossless-claw\|contextEngine\|lcm.db' | tee .sisyphus/evidence/task-3-lossless-claw-config.txt
    Expected: hits show allow-list entry, contextEngine slot, and dbPath
    Evidence: .sisyphus/evidence/task-3-lossless-claw-config.txt

  Scenario: Generated YAML does not contain plaintext placeholder drift
    Tool: Bash
    Steps: grep -rn 'REPLACE_ME\|PLACEHOLDER' modules/kubenix/apps/openclaw-config.enc.nix .k8s/apps/openclaw-config.enc.yaml | tee .sisyphus/evidence/task-3-placeholder-scan.txt
    Expected: no matches
    Evidence: .sisyphus/evidence/task-3-placeholder-scan.txt
  ```

  **Commit**: YES | Message: `feat(openclaw): enable lossless-claw fallback config` | Files: `modules/kubenix/apps/openclaw-config.enc.nix`

- [x] 4. Patch live CephFS config idempotently at startup

  **What to do**: edit the main container command in `modules/kubenix/apps/openclaw-nix.nix` so after seed-check and before gateway exec it runs this exact idempotent `jq` patch against `/home/node/.openclaw/openclaw.json`:
  ```sh
  jq '
    .plugins = (.plugins // {})
    | .plugins.enabled = true
    | .plugins.allow = (((.plugins.allow // []) + ["lossless-claw"]) | unique)
    | .plugins.slots = ((.plugins.slots // {})
        | .memory = (.memory // "memory-core")
        | .contextEngine = "lossless-claw")
    | .plugins.entries = ((.plugins.entries // {})
        | .["lossless-claw"] = ((.["lossless-claw"] // {})
            | .enabled = true
            | .config = ((.config // {})
                | .dbPath = "/home/node/.openclaw/lcm.db")))
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  ```
  Preserve all existing unrelated config keys and embedded secret values exactly as-is.
  **Must NOT do**: do not rewrite the whole config from template on every boot; do not remove the current env substitution block; do not touch provider/apiKey values; do not make rollout depend on manual editing of the live file.

  **Recommended Agent Profile**:
  - Category: `business-logic` — Reason: careful in-place JSON migration with scope guardrails.
  - Skills: [`writing-nix-code`] — shell/jq inside kubenix command string.
  - Omitted: [`developing-containers`] — no image mutation here.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T5 | Blocked By: T3

  **References**:
  - Pattern: `modules/kubenix/apps/openclaw-nix.nix:166-212` — current seed + env-substitution startup flow.
  - Pattern: `modules/kubenix/apps/openclaw-nix.nix:336-367` — CephFS mounts proving `/home/node/.openclaw` persistence.
  - Runtime truth: `/home/josevictor/Homelab/openclaw/openclaw.json:632-680` — live JSON fragment to migrate.
  - Tooling: `oci-images/openclaw-nix/default.nix:127-168` — `jq` already present in image toolchain.

  **Acceptance Criteria**:
  - [ ] startup command contains an idempotent `jq` patch for live config.
  - [ ] patch only touches plugin/context-engine fields and preserves existing secrets.
  - [ ] running the patch twice yields no additional diff on the JSON structure.

  **QA Scenarios**:
  ```
  Scenario: Startup script patch is rendered into manifest
    Tool: Bash
    Steps: make manifests && grep -n 'lossless-claw\|contextEngine\|jq' .k8s/apps/openclaw-nix.yaml | tee .sisyphus/evidence/task-4-startup-patch.txt
    Expected: manifest command includes jq patch logic and lossless-claw fields
    Evidence: .sisyphus/evidence/task-4-startup-patch.txt

  Scenario: Idempotent patch preserves existing config content
    Tool: Bash
    Steps: cp /home/josevictor/Homelab/openclaw/openclaw.json /tmp/openclaw-lossless-test.json && jq '.plugins = (.plugins // {}) | .plugins.enabled = true | .plugins.allow = (((.plugins.allow // []) + ["lossless-claw"]) | unique) | .plugins.slots = ((.plugins.slots // {}) | .memory = (.memory // "memory-core") | .contextEngine = "lossless-claw") | .plugins.entries = ((.plugins.entries // {}) | .["lossless-claw"] = ((.["lossless-claw"] // {}) | .enabled = true | .config = ((.config // {}) | .dbPath = "/home/node/.openclaw/lcm.db")))' /tmp/openclaw-lossless-test.json > /tmp/openclaw-lossless-test.tmp && mv /tmp/openclaw-lossless-test.tmp /tmp/openclaw-lossless-test.json && cp /tmp/openclaw-lossless-test.json /tmp/openclaw-lossless-test-2.json && jq '.plugins = (.plugins // {}) | .plugins.enabled = true | .plugins.allow = (((.plugins.allow // []) + ["lossless-claw"]) | unique) | .plugins.slots = ((.plugins.slots // {}) | .memory = (.memory // "memory-core") | .contextEngine = "lossless-claw") | .plugins.entries = ((.plugins.entries // {}) | .["lossless-claw"] = ((.["lossless-claw"] // {}) | .enabled = true | .config = ((.config // {}) | .dbPath = "/home/node/.openclaw/lcm.db")))' /tmp/openclaw-lossless-test-2.json > /tmp/openclaw-lossless-test-2.tmp && mv /tmp/openclaw-lossless-test-2.tmp /tmp/openclaw-lossless-test-2.json && diff -u /tmp/openclaw-lossless-test.json /tmp/openclaw-lossless-test-2.json | tee .sisyphus/evidence/task-4-idempotent-diff.txt
    Expected: empty diff output
    Evidence: .sisyphus/evidence/task-4-idempotent-diff.txt
  ```

  **Commit**: YES | Message: `feat(openclaw-nix): migrate live config for lossless-claw` | Files: `modules/kubenix/apps/openclaw-nix.nix`

- [x] 5. Run end-to-end repo verification for image + manifests

  **What to do**: run the full repo-side validation after T1-T4: build image, load image, inspect plugin files, run a podman smoke boot if feasible with disposable state/config dirs, run `make manifests`, inspect decrypted config manifest, scan generated outputs for obvious secret/plaintext regressions, and update any version constants required for the new image release path (`default.nix` version, `modules/commands.nix` `openclawVersion`, and pinned image tag in `modules/kubenix/apps/openclaw-nix.nix`) only if actual image release mechanics require it.
  **Must NOT do**: do not push images, commit, or git-push in this task unless the user explicitly approves during execution; do not mutate production cluster state.

  **Recommended Agent Profile**:
  - Category: `general` — Reason: multi-step verification across build/manifests/runtime.
  - Skills: [`developing-containers`,`writing-nix-code`] — image and manifest validation.
  - Omitted: [`kubernetes-tools`] — cluster mutation is out of scope here.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: F1-F4 | Blocked By: T1, T2, T3, T4

  **References**:
  - Test: `oci-images/openclaw-nix/RUNBOOK.md:5-114` — podman smoke commands.
  - Pattern: `modules/commands.nix:557-672` — `push-openclaw` version/tag/digest flow.
  - Pattern: `modules/kubenix/apps/openclaw-nix.nix:49-57` — pinned image location to update if needed.
  - Pattern: `oci-images/openclaw-nix/default.nix:121-123,273-337` — image tag/version source.

  **Acceptance Criteria**:
  - [ ] image build succeeds.
  - [ ] plugin files are present in the loaded image.
  - [ ] manifests regenerate cleanly.
  - [ ] no new plaintext secret regressions appear in source or generated YAML.

  **QA Scenarios**:
  ```
  Scenario: Full repo-side verification passes
    Tool: Bash
    Steps: nix build .#openclaw-nix-image |& tee .sisyphus/evidence/task-5-image-build.txt && make manifests |& tee .sisyphus/evidence/task-5-make-manifests.txt
    Expected: both commands exit 0
    Evidence: .sisyphus/evidence/task-5-image-build.txt

  Scenario: Secret/plaintext regression scan stays clean
    Tool: Bash
    Steps: grep -rn 'sk-\|ghp_\|ghs_\|github_pat_' modules/kubenix/apps/openclaw-config.enc.nix .k8s/apps/openclaw-config.enc.yaml .k8s/apps/openclaw-nix.yaml | tee .sisyphus/evidence/task-5-secret-scan.txt
    Expected: no new plaintext secret hits in repo source or generated YAML beyond known local CephFS runtime file outside repo
    Evidence: .sisyphus/evidence/task-5-secret-scan.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: `n/a`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `feat(openclaw-nix): package lossless-claw deps`
- Commit 2: `feat(openclaw-nix): bundle lossless-claw plugin`
- Commit 3: `feat(openclaw): enable lossless-claw config`
- Commit 4: `feat(openclaw-nix): migrate live config for lossless-claw`
- Do **not** push git or publish GHCR image without explicit user approval during execution.

## Success Criteria
- `lossless-claw` is bundled into the image deterministically.
- Repo fallback config points OpenClaw context-engine traffic to `lossless-claw`.
- Existing live CephFS config self-migrates on startup for non-secret plugin fields.
- `memory-core` remains intact for the memory slot.
- Validation evidence proves image + manifests are healthy.
- Migration/backfill remains excluded unless discovered to be trivial during execution.

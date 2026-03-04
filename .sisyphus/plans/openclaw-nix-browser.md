# Add headless Chromium to `openclaw-nix` image + wire OpenClaw config

## TL;DR
> **Summary**: Bake nixpkgs Chromium (+ fontconfig/fonts) into `openclaw-nix` OCI image and configure OpenClaw to use fixed `/bin/chromium` with `noSandbox=true`.
> **Deliverables**: updated image build, updated kubenix config template, smoke QA (podman + cluster).
> **Effort**: Short
> **Parallel**: YES — 2 waves
> **Critical Path**: Image Nix edits → `nix build`+podman smoke → bump tag in kubenix → `make manifests` → rollout QA

## Context

### Original Request
- openclaw-nix container has no browser installed.
- Need headless browser available for agents.
- Browser binary path must be stable (not referencing `/nix/store` directly); symlink acceptable.

### Interview Summary
- Browser: **Chromium**.
- Execution model: **in-container host browser** (not sandbox-browser sidecar).
- Config surface: set via **OpenClaw config template** (not env vars).
- Tag strategy: **bump to `v2026.3.2-v2`**.
- Sandbox browser: **disable**.

### Sandbox sessions (important)
OpenClaw `browser` tool defaults `target=sandbox` in sandboxed sessions if a sandbox bridge URL is present. Our approach is **host-mode Chromium in the same container**, not a separate sandbox-browser.

Decision: set `agents.defaults.sandbox.browser.enabled=false` so browser tool defaults to host Chromium.

### Metis Review (gaps addressed)
- Add fonts + fontconfig and wire `FONTCONFIG_FILE` to prevent headless Chromium failures.
- Ensure OpenClaw config sets `browser.executablePath` and `browser.noSandbox`.

## Work Objectives

### Core Objective
Enable OpenClaw browser tool to reliably launch a headless Chromium inside the `openclaw-nix` container.

### Deliverables
- `oci-images/openclaw-nix/default.nix`: include Chromium + fontconfig + fonts; ensure stable `/bin/chromium`.
- `modules/kubenix/apps/openclaw-nix.nix`: set `browser.executablePath = "/bin/chromium"`, `browser.noSandbox = true`.
- Bump image tag usage to `v2026.3.2-v2` (image build tag + kubenix deployment + push cmd) **without changing upstream OpenClaw source version**.
- Update `oci-images/openclaw-nix/RUNBOOK.md` with browser smoke checks.

### Definition of Done (agent-verifiable)
- [ ] `nix build .#openclaw-nix-image` succeeds.
- [ ] After `podman load`, container has working Chromium at `/bin/chromium` and can run a headless fetch.
- [ ] `make manifests` succeeds and rendered `.k8s/apps/openclaw-nix*.yaml` references tag `v2026.3.2-v2`.
- [ ] In-cluster: `/bin/chromium --version` works in `openclaw-nix` pod; OpenClaw config contains executablePath `/bin/chromium` and noSandbox=true.

### Must Have
- Stable browser path: `/bin/chromium` (top-layer symlink).
- Kubernetes-friendly: `browser.noSandbox=true`.
- Fonts available (avoid blank pages / fontconfig errors).

### Must NOT Have
- Do NOT add Docker-in-Docker / sandbox-browser orchestration.
- Do NOT edit generated `.k8s/*.yaml` directly.
- Do NOT hardcode secrets.

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.

- Test decision: tests-after = none (smoke QA only).
- Evidence: save command outputs under `.sisyphus/evidence/task-*-*.txt`.

## Execution Strategy

### Parallel Execution Waves

Wave 1 (parallel):
- Image build changes (Chromium + fonts + env)
- Kubenix config changes (browser.executablePath/noSandbox + tag bump)
- Runbook updates

Wave 2 (depends on Wave 1):
- Local image smoke QA (nix build + podman)
- Manifest gen + cluster rollout QA

### Dependency Matrix
- T1 blocks T4/T5
- T2 blocks T5
- T3 blocks T5
- T4 blocks T5

### Agent Dispatch Summary
- Wave 1: 3 tasks (writing-nix-code, developing-containers)
- Wave 2: 2 tasks (developing-containers, kubernetes-tools)

## TODOs

- [ ] 1. Add Chromium + font stack to `openclaw-nix` OCI image

  **What to do**:
  - Edit `oci-images/openclaw-nix/default.nix`:
    - In `cliTools = pkgs.buildEnv { paths = [ ... ]; }` add these packages:
      - `pkgs.chromium`
      - `pkgs.fontconfig` (for `fc-list` + runtime font discovery)
      - fonts (pick a minimal but reliable set):
        - `pkgs.dejavu_fonts`
        - `pkgs.noto-fonts`
        - `pkgs.noto-fonts-color-emoji` (emoji)
        - (optional if CJK needed) `pkgs.noto-fonts-cjk-sans`
    - Generate a fonts.conf and ship it in image:
      - Add a let-binding: `fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts pkgs.noto-fonts pkgs.noto-fonts-color-emoji pkgs.noto-fonts-cjk-sans ]; };`
      - In `extraCommands`, create `./etc/fonts` and copy/symlink `${fontsConf}` to `./etc/fonts/fonts.conf`.
    - Add env var to image config: `FONTCONFIG_FILE=/etc/fonts/fonts.conf`.
  - Rationale: Chromium often fails/headless renders blank without fonts+fontconfig.

  **Must NOT do**:
  - Do not rely on Playwright browser downloads.
  - Do not add setuid sandbox; we will run with noSandbox.

  **Recommended Agent Profile**:
  - Category: `general` — Nix + container build
  - Skills: [`writing-nix-code`, `developing-containers`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4, 5 | Blocked By: none

  **References**:
  - Image build: `oci-images/openclaw-nix/default.nix` (cliTools + extraCommands already symlink bins into /bin)
  - OpenClaw browser docs: https://github.com/openclaw/openclaw/blob/main/docs/tools/browser.md
  - OpenClaw browser types: https://github.com/openclaw/openclaw/blob/main/src/config/types.browser.ts

  **Acceptance Criteria**:
  - [ ] `rg -n "chromium" oci-images/openclaw-nix/default.nix` shows chromium included.
  - [ ] `podman run` shows `FONTCONFIG_FILE=/etc/fonts/fonts.conf` and the file exists.

  **QA Scenarios**:
  ```
  Scenario: Image includes /bin/chromium
    Tool: Bash
    Steps:
      1. nix build .#openclaw-nix-image
      2. podman load < result | tee .sisyphus/evidence/task-1-podman-load.txt
      3. podman run --rm localhost/openclaw-nix:v2026.3.2-v2 sh -lc 'ls -la /bin/chromium && readlink -f /bin/chromium'
    Expected: /bin/chromium exists; readlink resolves
    Evidence: .sisyphus/evidence/task-1-chromium-path.txt

  Scenario: Fontconfig works
    Tool: Bash
    Steps:
      1. podman run --rm localhost/openclaw-nix:v2026.3.2-v2 sh -lc 'echo "FONTCONFIG_FILE=$FONTCONFIG_FILE"; test -f "$FONTCONFIG_FILE"; fc-list | head'
    Expected: env var set + file exists; fc-list prints at least 1 font
    Evidence: .sisyphus/evidence/task-1-fonts.txt
  ```

  **Commit**: YES | Message: `build(openclaw-nix): add chromium + fonts for browser tool` | Files: [oci-images/openclaw-nix/default.nix]


- [ ] 2. Configure OpenClaw to use `/bin/chromium` (headless + noSandbox)

  **What to do**:
  - Edit `modules/kubenix/apps/openclaw-nix.nix` config template:
    - In the top-level `browser = { ... }` object, add:
      - `executablePath = "/bin/chromium";`
      - `noSandbox = true;`
      - keep `headless = true;` and current flags.
      - add Chromium-friendly args: `extraArgs = [ "--disable-dev-shm-usage" "--disable-gpu" ];`
  - In `agents.defaults.sandbox.browser`, set `enabled = false;` (disable sandbox-browser).

  **Must NOT do**:
  - Do not move browser config into secrets env.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5 | Blocked By: none

  **References**:
  - OpenClaw config labels: https://github.com/openclaw/openclaw/blob/main/src/config/schema.labels.ts
  - OpenClaw help: https://github.com/openclaw/openclaw/blob/main/src/config/schema.help.ts

  **Acceptance Criteria**:
  - [ ] `rg -n "executablePath = \"/bin/chromium\"" modules/kubenix/apps/openclaw-nix.nix` matches.
  - [ ] `rg -n "noSandbox = true" modules/kubenix/apps/openclaw-nix.nix` matches.
  - [ ] `rg -n "agents\.defaults\.sandbox\.browser" modules/kubenix/apps/openclaw-nix.nix` shows `enabled = false;`.

  **QA Scenarios**:
  ```
  Scenario: Generated config contains browser executablePath
    Tool: Bash
    Steps:
      1. git add modules/kubenix/apps/openclaw-nix.nix
      2. make manifests
      3. rg -n 'executablePath|noSandbox|extraArgs|/bin/chromium' .k8s/apps/openclaw-nix.yaml
    Expected: rendered manifest includes executablePath=/bin/chromium and noSandbox=true
    Evidence: .sisyphus/evidence/task-2-rendered-config.txt

  Scenario: Cluster config file contains browser settings
    Tool: Bash
    Steps:
      1. kubectl exec -n apps deploy/openclaw-nix -c main -- sh -lc 'jq -r .browser.executablePath /home/node/.openclaw/openclaw.json; jq -r .browser.noSandbox /home/node/.openclaw/openclaw.json'
    Expected: prints /bin/chromium and true
    Evidence: .sisyphus/evidence/task-2-incluster-config.txt
  ```

  **Commit**: YES | Message: `feat(openclaw-nix): set browser executablePath to /bin/chromium` | Files: [modules/kubenix/apps/openclaw-nix.nix]


- [ ] 3. Bump image tag to `v2026.3.2-v2` everywhere

  **What to do**:
  - IMPORTANT: in `oci-images/openclaw-nix/default.nix`, `version` is used to fetch upstream OpenClaw source at `rev = "v${version}"`. Do NOT change it to a non-existent upstream tag.
  - Implement image tag bump by separating **OpenClaw source version** from **image tag**:
    - Keep: `version ? "2026.3.2"`
    - Add: `imageTagSuffix = "-v2"; imageTag = "v${version}${imageTagSuffix}";`
    - Change `dockerTools.streamLayeredImage.tag = imageTag`.
  - Edit `modules/kubenix/apps/openclaw-nix.nix` to set deployment `image.tag = "v2026.3.2-v2"`.
  - Verify `modules/commands.nix` push command still tags/pushes the correct version:
    - Update `openclawVersion` to `2026.3.2-v2`.
  - Update any other references (Makefile docs, runbooks) that mention the old tag.

  **Must NOT do**:
  - Do not overwrite `v2026.3.2`.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: [`writing-nix-code`, `git-master`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4, 5 | Blocked By: none

  **References**:
  - Flake package: `flake.nix` → `openclaw-nix-image` import
  - Push cmd: `modules/commands.nix` (`push-openclaw`)
  - K8s app: `modules/kubenix/apps/openclaw-nix.nix`

  **Acceptance Criteria**:
  - [ ] `rg -n "2026\.3\.2-v2" -S oci-images/openclaw-nix/default.nix modules/kubenix/apps/openclaw-nix.nix modules/commands.nix` finds all 3.

  **QA Scenarios**:
  ```
  Scenario: Built image tag matches version
    Tool: Bash
    Steps:
      1. nix build .#openclaw-nix-image
      2. podman load < result
      3. podman images | rg -n 'localhost/openclaw-nix\s+v2026\.3\.2-v2'
    Expected: image exists with that tag
    Evidence: .sisyphus/evidence/task-3-image-tag.txt
  ```

  **Commit**: YES | Message: `chore(openclaw-nix): bump image tag to v2026.3.2-v2` | Files: [oci-images/openclaw-nix/default.nix, modules/kubenix/apps/openclaw-nix.nix, modules/commands.nix]


- [ ] 4. Local smoke QA: Chromium headless works

  **What to do**:
  - Build/load image.
  - Run a real headless request:
    - `chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --dump-dom https://example.com | rg -n "Example Domain"`

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: [`developing-containers`]

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocked By: 1, 3

  **Acceptance Criteria**:
  - [ ] Command exits 0 and DOM contains “Example Domain”.

  **QA Scenarios**:
  ```
  Scenario: Headless fetch works
    Tool: Bash
    Steps:
      1. podman run --rm localhost/openclaw-nix:v2026.3.2-v2 sh -lc 'chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --dump-dom https://example.com | rg -n "Example Domain"'
    Expected: rg finds match; exit 0
    Evidence: .sisyphus/evidence/task-4-headless-fetch.txt

  Scenario: Failure mode shows actionable error
    Tool: Bash
    Steps:
      1. podman run --rm -e FONTCONFIG_FILE=/nope localhost/openclaw-nix:v2026.3.2-v2 sh -lc 'chromium --headless --no-sandbox --dump-dom https://example.com' || true
    Expected: non-zero exit; stderr indicates fontconfig/file problem
    Evidence: .sisyphus/evidence/task-4-fontconfig-fail.txt
  ```

  **Commit**: NO


- [ ] 5. K8s rollout + in-cluster browser verification

  **What to do**:
  - Push updated image to GHCR using `nix run .#push-openclaw` (after updating version).
  - Run `make manifests` (ensure new/changed files are staged if needed; flake evaluates git tree).
  - Let Flux reconcile, or force reconcile if needed.
  - Verify in cluster:
    - `/bin/chromium --version`
    - config contains `/bin/chromium` + noSandbox.
    - (optional) trigger a simple browser tool action via OpenClaw API if exposed.

  **Recommended Agent Profile**:
  - Category: `kubernetes-tools`
  - Skills: [`kubernetes-tools`, `git-master`]

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocked By: 1, 2, 3, 4

  **Acceptance Criteria**:
  - [ ] `kubectl logs` shows no browser spawn errors.
  - [ ] `kubectl exec ... -- /bin/chromium --version` exit 0.

  **QA Scenarios**:
  ```
  Scenario: Browser binary works in pod
    Tool: Bash
    Steps:
      1. kubectl -n apps rollout status deploy/openclaw-nix --timeout=10m
      2. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc '/bin/chromium --version'
    Expected: prints version; exit 0
    Evidence: .sisyphus/evidence/task-5-incluster-chromium-version.txt

  Scenario: OpenClaw browser tool no longer complains about missing browser
    Tool: Bash
    Steps:
      1. kubectl -n apps logs deploy/openclaw-nix -c main --tail=400 | rg -n 'browser|chromium|executable|spawn|ENOENT|sandbox' || true
    Expected: no ENOENT for chromium; no “No browser found” messages
    Evidence: .sisyphus/evidence/task-5-logs-scan.txt
  ```

  **Commit**: YES | Message: `deploy(openclaw-nix): roll out chromium-enabled image v2026.3.2-v2` | Files: [all changed nix files + regenerated .k8s]


## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Runtime QA (podman + k8s) — unspecified-high
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Prefer 2 commits:
  1) image build + fonts
  2) kubenix wiring + tag bump
- Do not commit secrets.

## Success Criteria
- Browser tool has a working headless Chromium available at stable `/bin/chromium`.
- No sandbox-browser sidecar/DIND added.
- `make manifests` passes and cluster deploy runs on new tag `v2026.3.2-v2`.

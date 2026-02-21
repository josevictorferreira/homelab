# OpenClaw `openclaw-nix` OCI image (Nix-built) — plan

## TL;DR
> Build a linux/amd64 OCI image as a **flake package** using `openclaw/nix-openclaw` packages + extra toolchain, with a k8s-friendly layout: `/config` ephemeral (seeded from image template each start), `/state` persistent (workspace + creds/sessions + skills/extensions + tool installs/caches), `/logs` persistent. Validate via rootless Podman smoke QA (`--userns=keep-id`).

**Deliverables**
- Flake package producing OCI tarball for image `openclaw-nix`
- Entrypoint that seeds `/config/openclaw.json` from template + `${ENV}` substitution (allowlist)
- Baseline config template matching current kubenix behavior (matrix+whatsapp enabled) but WITHOUT known bug
- Documented local Podman smoke QA commands + volume map

**Estimated Effort**: Medium
**Parallel Execution**: YES (3 waves)
**Critical Path**: nix-openclaw integration → image derivation → podman smoke QA

---

## Context

### Original Request
- Replace current `modules/kubenix/apps/openclaw.nix` init-container approach by baking requirements into a base image.
- Use Nix to build an OCI image (push to GHCR later; local testing now).
- Design volumes per OpenClaw docs; persist tool installs + workspace + logs; config resets each start from image template.

### Key Decisions (confirmed)
- Build source: **openclaw/nix-openclaw** packaging (wrap into OCI here).
- Platforms: **linux/amd64 only**.
- Build interface: **flake package only** (`nix build .#...`).
- Runtime test: **rootless Podman**, prefer `--userns=keep-id`.
- Persistence:
  - `/state`: OpenClaw state (creds/sessions), skills/extensions, tool installs/caches, and workspace at `/state/workspace`
  - `/logs`: persistent logs
  - `/config`: ephemeral; re-seeded each start from image template
- Baseline config: match current behavior (matrix + whatsapp enabled) and do `${ENV}` placeholder substitution at startup.
- Config edits at runtime are OK to be lost on restart.
- Bake-in toolchain (same as today): curl, jq, git, python3 + uv/pip (+ requests), ffmpeg, gh, gemini-cli, npm.

### Existing repo precedent
- `images/openclaw-matrix.nix` already builds an OpenClaw-derived image via `dockerTools.*` (but uses different approach; slated for removal later).
- Repo image patterns: `dockerTools.buildImage` / `dockerTools.buildLayeredImage`; helper commands exist but are Docker-based (`modules/commands.nix`).

---

## Work Objectives

### Core Objective
Produce a reproducible Nix-built OCI image `openclaw-nix` (linux/amd64) suitable for later K8s use, validated locally with Podman.

### Definition of Done
- [ ] `nix build .#openclaw-nix-image` succeeds on linux builder
- [ ] Result tarball loads into Podman and runs OpenClaw gateway with mounted `/state` + `/logs`
- [ ] Config seeding + `${ENV}` substitution works; config remains ephemeral
- [ ] Toolchain binaries are available; runtime tool installs persist in `/state`

### Must NOT Have (Guardrails)
- No runtime network installs in entrypoint (no `apt-get`, no runtime `npm install` for baked deps)
- No hardcoded secrets in repo (only `${ENV}` placeholders)
- No reliance on systemd inside container
- Don’t remove `images/openclaw-matrix.nix` in this work (remove later after validation)

---

## Verification Strategy

> **Agent-executed only** (no “user manually checks”). Evidence saved under `.sisyphus/evidence/`.

### Automated Tests
- None required (smoke QA only).

### Smoke QA (required)
- `nix build` on linux (or macOS via remote builder)
- `podman load` + `podman run --userns=keep-id` with bind mounts
- Validate gateway starts, writes logs to `/logs`, creates/uses `/state/*`, and toolchain is present

---

## Execution Strategy

### Parallel Waves

Wave 1 — specs + building blocks (parallel)
- T1: nix-openclaw integration + wrapper contract discovery
- T2: filesystem + env contract for persistence/tool installs
- T3: baseline config template (matrix+whatsapp) + bugfix
- T4: entrypoint: seed config + allowlist `${ENV}` substitution
- T5: package `gemini-cli` (Nix) if not in nixpkgs

Wave 2 — image derivation + docs (parallel)
- T6: flake package: `openclaw-nix` OCI image (dockerTools stream/layer)
- T7: ensure matrix/whatsapp extension deps are baked-in (no runtime npm install)
- T8: local runbook: Podman smoke QA commands + volume map

Wave 3 — smoke QA on real builders (parallel)
- T9: Linux builder smoke QA (build→load→run→assert)
- T10: macOS + remote builder smoke QA (same assertions)

---

## TODOs

- [ ] 1. Pin `nix-openclaw` input + pick runtime entry binary/args

  **What to do**:
  - Add `openclaw/nix-openclaw` as a pinned flake input (rev + narHash).
  - Decide the container entry binary + args:
    - Prefer nix-openclaw wrapper (`openclaw` or `openclaw-gateway`) executing the gateway (docs: gateway run).
  - Record the runtime contract: which env vars we will set and why.

  **Must NOT do**:
  - No secrets in git.
  - Don’t build via `nix-build images/<name>.nix` (flake package only).

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `managing-flakes`, `writing-nix-code`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2-5)
  - **Blocks**: 6, 7
  - **Blocked By**: None

  **References**:
  - nix-openclaw:
    - https://github.com/openclaw/nix-openclaw
    - `nix/packages/openclaw-gateway.nix`
    - `nix/scripts/gateway-install.sh` (wrapper)
    - `nix/modules/home-manager/openclaw/config.nix` (path defaults)
  - OpenClaw env vars: https://docs.openclaw.ai/help/environment.md

  **Acceptance Criteria**:
  - [ ] `nix flake lock` contains pinned `nix-openclaw` with fixed rev/hash
  - [ ] Selected entry binary documented in plan comments/readme (what we exec)

  **QA Scenarios**:
  ```
  Scenario: Build and confirm openclaw binary exists
    Tool: Bash
    Steps:
      1. nix build .#<openclaw-binary-pkg>
      2. ls -la result/bin | rg -n "openclaw"
    Expected Result: openclaw entry binary present
    Evidence: .sisyphus/evidence/task-1-openclaw-bin.txt
  Scenario: Confirm env vars are the documented ones
    Tool: Bash
    Steps:
      1. rg -n "OPENCLAW_(STATE_DIR|CONFIG_PATH|LOG_DIR)" -S <changed-files>
    Expected Result: only expected env vars used
    Evidence: .sisyphus/evidence/task-1-envvar-scan.txt
  ```

- [ ] 2. Define filesystem + env contract for `/config` (ephemeral), `/state` + `/logs` (persistent)

  **What to do**:
  - Finalize volume map + exact paths:
    - `OPENCLAW_STATE_DIR=/state/.openclaw` (so `~/.openclaw/*` maps into `/state/.openclaw/*`)
    - workspace at `/state/workspace` (and config sets `agents.defaults.workspace` to it)
    - `OPENCLAW_CONFIG_PATH=/config/openclaw.json`
    - logs to `/logs` (via config `logging.file.path`)
    - set `HOME=/state/home` (persistent, writable under keep-id)
  - Persist “tool installs” by standardizing prefixes into `/state`:
    - `PATH=/state/bin:/state/npm/bin:<nix-paths>`
    - `NPM_CONFIG_PREFIX=/state/npm`, `NPM_CONFIG_CACHE=/state/npm-cache`
    - `UV_CACHE_DIR=/state/uv-cache`, `PIP_CACHE_DIR=/state/pip-cache`
    - `XDG_CACHE_HOME=/state/xdg-cache`, `XDG_DATA_HOME=/state/xdg-data`
  - Rootless Podman policy: no runtime `chown`; recommend run flags.

  **Must NOT do**:
  - Don’t persist config.
  - Don’t rely on being UID 0 inside container.

  **Recommended Agent Profile**:
  - **Category**: `general`
  - **Skills**: `developing-containers`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 6, 8, 9, 10
  - **Blocked By**: None

  **References**:
  - Env vars: https://docs.openclaw.ai/help/environment.md
  - Workspace/skills precedence:
    - https://docs.openclaw.ai/concepts/agent-workspace.md
    - https://docs.openclaw.ai/tools/skills.md
  - Logging: https://docs.openclaw.ai/gateway/logging.md

  **Acceptance Criteria**:
  - [ ] Runbook includes exact `podman run` command with `--userns=keep-id --user $(id -u):$(id -g)`
  - [ ] Documented map covers: config, state, workspace, logs, npm/uv/pip caches

  **QA Scenarios**:
  ```
  Scenario: Rootless write probe for /state and /logs
    Tool: Bash
    Steps:
      1. mkdir -p /tmp/openclaw-state /tmp/openclaw-logs
      2. podman run --rm --userns=keep-id --user $(id -u):$(id -g) \
           -v /tmp/openclaw-state:/state \
           -v /tmp/openclaw-logs:/logs \
           --entrypoint sh <IMAGE> -c 'id; touch /state/probe /logs/probe'
    Expected Result: exit 0; probe files created
    Evidence: .sisyphus/evidence/task-2-rootless-probe.txt
  Scenario: Tool prefixes point into /state
    Tool: Bash
    Steps:
      1. podman run --rm --userns=keep-id --user $(id -u):$(id -g) \
           -v /tmp/openclaw-state:/state --entrypoint sh <IMAGE> -c 'echo $PATH; echo $NPM_CONFIG_PREFIX; echo $UV_CACHE_DIR'
    Expected Result: shows /state/* paths
    Evidence: .sisyphus/evidence/task-2-prefix-env.txt
  ```

- [ ] 3. Create baseline config template (matrix + whatsapp) with `/state/workspace` + `/logs`

  **What to do**:
  - Add a config template embedded in image (JSON5 ok per docs) that:
    - enables matrix + whatsapp plugins like current kubenix behavior
    - sets `agents.defaults.workspace = "/state/workspace"`
    - configures logging to `/logs`
    - contains `${ENV}` placeholders only (no secrets)
  - Fix known bug: don’t set `OPENROUTER_API_KEY` to `${OPENCLAW_MATRIX_TOKEN}`.

  **Must NOT do**:
  - No provider keys/token literals.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `writing-nix-code`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 4, 6
  - **Blocked By**: None

  **References**:
  - Config: https://docs.openclaw.ai/gateway/configuration.md
  - Config ref: https://docs.openclaw.ai/gateway/configuration-reference.md
  - Logging: https://docs.openclaw.ai/gateway/logging.md
  - Current behavior: `modules/kubenix/apps/openclaw.nix` (enables matrix+whatsapp + placeholder substitution)

  **Acceptance Criteria**:
  - [ ] Template sets workspace to `/state/workspace`
  - [ ] Template logs to `/logs`
  - [ ] `rg -n "OPENROUTER_API_KEY.*OPENCLAW_MATRIX_TOKEN" -S <template>` returns no hits

  **QA Scenarios**:
  ```
  Scenario: Template contains required dirs and no secrets
    Tool: Bash
    Steps:
      1. rg -n "/state/workspace|/logs" -S <template-path>
      2. rg -n "(API_KEY|TOKEN)\s*[:=]\s*\"[^$]" -S <template-path> || true
    Expected Result: first grep hits; second has no hits
    Evidence: .sisyphus/evidence/task-3-template-sanity.txt
  Scenario: Template enables matrix + whatsapp
    Tool: Bash
    Steps:
      1. rg -n "matrix" -S <template-path>
      2. rg -n "whatsapp" -S <template-path>
    Expected Result: both present under plugin/channel config
    Evidence: .sisyphus/evidence/task-3-template-plugins.txt
  ```

- [ ] 4. Implement entrypoint: seed `/config/openclaw.json` + allowlist `${ENV}` substitution

  **What to do**:
  - Add an entrypoint script that on each container start:
    1) recreates `/config` (ephemeral)
    2) copies template → `/config/openclaw.json`
    3) substitutes `${VAR}` placeholders for an explicit allowlist (same list as today’s kubenix script + any added)
    4) execs gateway process
  - Ensure it does NOT wipe `/state`.
  - Ensure it works without root permissions.

  **Must NOT do**:
  - No runtime package installs.
  - No chmod/chown on mounted volumes.

  **Recommended Agent Profile**:
  - **Category**: `general`
  - **Skills**: `developing-containers`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 6
  - **Blocked By**: 2, 3

  **References**:
  - Current substitution logic (reference only): `modules/kubenix/apps/openclaw.nix` (node script replacing `${ENV}`)
  - Env var docs: https://docs.openclaw.ai/help/environment.md

  **Acceptance Criteria**:
  - [ ] Starting container creates `/config/openclaw.json` every time
  - [ ] Placeholder substitution occurs only for allowlisted vars

  **QA Scenarios**:
  ```
  Scenario: Config is re-seeded each start
    Tool: Bash
    Steps:
      1. podman run --rm --userns=keep-id --user $(id -u):$(id -g) -v /tmp/openclaw-state:/state -v /tmp/openclaw-logs:/logs <IMAGE> sh -c 'cat /config/openclaw.json | head'
      2. podman run --rm --userns=keep-id --user $(id -u):$(id -g) -v /tmp/openclaw-state:/state -v /tmp/openclaw-logs:/logs <IMAGE> sh -c 'cat /config/openclaw.json | head'
    Expected Result: file exists both runs; contents match template+substitution
    Evidence: .sisyphus/evidence/task-4-config-seed.txt
  Scenario: Substitution works for one allowlisted var
    Tool: Bash
    Steps:
      1. podman run --rm -e OPENCLAW_MATRIX_TOKEN=abc123 --userns=keep-id --user $(id -u):$(id -g) -v /tmp/openclaw-state:/state -v /tmp/openclaw-logs:/logs <IMAGE> sh -c 'rg -n "abc123" /config/openclaw.json'
    Expected Result: grep finds abc123
    Evidence: .sisyphus/evidence/task-4-subst-works.txt
  ```

- [ ] 5. Ensure required toolchain is present (Nix, not runtime installs)

  **What to do**:
  - Include in image closure + PATH (Nix store ok):
    - `curl`, `jq`, `git`
    - `python3` + `pip`
    - `uv`
    - `ffmpeg`
    - `gh`
    - `gemini` CLI (Nix package or local derivation)
    - `node` + `npm` (user-driven persistent installs under `/state`)
  - Ensure TLS works: include `cacert` and set `SSL_CERT_FILE`.
  - Ensure `/tmp` and `/var/tmp` exist and are writable (1777).

  **Must NOT do**:
  - Don’t reintroduce runtime `apt-get` / curl installers.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `developing-containers`, `writing-nix-code`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 6, 9, 10
  - **Blocked By**: None

  **References**:
  - Current runtime-installed tool list: `modules/kubenix/apps/openclaw.nix` (install-tools initContainer)
  - Image patterns: `images/mcpo.nix`, `images/openclaw-matrix.nix`

  **Acceptance Criteria**:
  - [ ] Running each binary prints a version (non-zero exit fails)
  - [ ] `/tmp` and `/var/tmp` are writable under rootless Podman

  **QA Scenarios**:
  ```
  Scenario: Toolchain versions
    Tool: Bash
    Steps:
      1. podman run --rm --userns=keep-id --user $(id -u):$(id -g) <IMAGE> sh -c '
           set -e
           curl --version
           jq --version
           git --version
           python3 --version
           pip --version
           uv --version
           ffmpeg -version | head -1
           gh --version
           gemini --version || true
           node --version
           npm --version
         '
    Expected Result: commands succeed; gemini may be pending until packaged
    Evidence: .sisyphus/evidence/task-5-toolchain-versions.txt
  Scenario: tmp dirs writable
    Tool: Bash
    Steps:
      1. podman run --rm --userns=keep-id --user $(id -u):$(id -g) <IMAGE> sh -c 'touch /tmp/probe /var/tmp/probe'
    Expected Result: exit 0
    Evidence: .sisyphus/evidence/task-5-tmp-writable.txt
  ```

- [ ] 6. Build `openclaw-nix` OCI image as flake package (linux/amd64)

  **What to do**:
  - Add flake output: `packages.x86_64-linux.openclaw-nix-image` producing an OCI tarball.
  - Prefer `dockerTools.streamLayeredImage` for big closures (or `buildLayeredImage` if stream is awkward with your registry flow).
  - Include:
    - OpenClaw gateway runtime from nix-openclaw (Task 1)
    - entrypoint + config template (Tasks 3-4)
    - toolchain packages (Task 5)
    - filesystem scaffolding: `/config`, `/state`, `/logs`, `/tmp`, `/var/tmp`
  - Container metadata:
    - `Cmd` uses entrypoint
    - `Env` sets `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`, tool prefixes
    - `ExposedPorts`: `18789/tcp`
    - **Do NOT set `User` in image** (to support `podman --user $(id -u):$(id -g)` + `--userns=keep-id`).
    - Set embedded image name/tag to something stable for local use, e.g. `localhost/openclaw-nix:dev`.

  **Must NOT do**:
  - No systemd.
  - No hardcoded secrets.

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: `writing-nix-code`, `developing-containers`, `managing-flakes`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: 7, 8, 9, 10
  - **Blocked By**: 1-5

  **References**:
  - Repo patterns: `images/mcpo.nix`, `images/docling-rocm.nix`
  - OpenClaw docs:
    - env vars: https://docs.openclaw.ai/help/environment.md
    - config: https://docs.openclaw.ai/gateway/configuration.md
    - logging: https://docs.openclaw.ai/gateway/logging.md

  **Acceptance Criteria**:
  - [ ] `nix build .#openclaw-nix-image` produces a tarball at `./result`
  - [ ] `podman load < result` succeeds

  **QA Scenarios**:
  ```
  Scenario: Build + load OCI image
    Tool: Bash
    Steps:
      1. nix build .#openclaw-nix-image
      2. podman load < result
      3. podman images | rg -n "openclaw-nix"
    Expected Result: image appears in podman image list
    Evidence: .sisyphus/evidence/task-6-build-load.txt
  ```

- [ ] 7. Bake in matrix/whatsapp deps (no runtime `npm install`)

  **What to do**:
  - Identify what OpenClaw expects for matrix/whatsapp support.
    - Current kubenix does `npm install` under `/app/extensions/matrix`.
  - Ensure required JS deps exist at runtime without network installs.
    - Prefer Nix packaging + `NODE_PATH` rather than mutable `node_modules`.
  - Ensure persistent plugin/skills dirs are under `/state` (not `/config`).

  **Must NOT do**:
  - No runtime `npm install` in entrypoint.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: `developing-containers`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: 9, 10
  - **Blocked By**: 6

  **References**:
  - Current runtime install: `modules/kubenix/apps/openclaw.nix` (matrix extension npm install)
  - Existing precedent: `images/openclaw-matrix.nix` (installs matrix-bot-sdk)
  - Docs:
    - plugins: https://docs.openclaw.ai/tools/plugin.md
    - skills: https://docs.openclaw.ai/tools/skills.md

  **Acceptance Criteria**:
  - [ ] Container can start with `--network=none` (no dependency installs) and still initializes matrix/whatsapp bits

  **QA Scenarios**:
  ```
  Scenario: Offline start (no runtime installs)
    Tool: Bash
    Steps:
      1. rm -rf /tmp/openclaw-state /tmp/openclaw-logs; mkdir -p /tmp/openclaw-state /tmp/openclaw-logs
      2. podman run -d --name openclaw-nix-offline --network=none --userns=keep-id --user $(id -u):$(id -g) \
           -v /tmp/openclaw-state:/state -v /tmp/openclaw-logs:/logs \
           -p 18789:18789 <IMAGE>
      3. sleep 3
      4. (curl may fail under --network=none if it needs DNS; we only test local port bind) \
         bash -lc 'nc -z 127.0.0.1 18789 && echo OK || echo FAIL'
      5. podman logs openclaw-nix-offline | tee .sisyphus/evidence/task-7-offline-start.txt
      6. podman rm -f openclaw-nix-offline
    Expected Result: process starts; TCP connect works (HTTP code not 000); logs mention matrix/whatsapp init (best-effort)
    Evidence: .sisyphus/evidence/task-7-offline-start.txt
  ```

- [ ] 8. Add local Podman smoke QA runbook (volumes + env + expected outputs)

  **What to do**:
  - Add concise docs in repo (or in plan) showing:
    - build: `nix build .#openclaw-nix-image`
    - load: `podman load < result`
    - run: `podman run --userns=keep-id --user $(id -u):$(id -g) ...`
    - required mounts: `/state`, `/logs`
    - optional: port publishing `-p 18789:18789`
    - example env vars to prove substitution

  **Recommended Agent Profile**:
  - **Category**: `writing`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: 9, 10, F1
  - **Blocked By**: 2, 6

  **References**:
  - OpenClaw docker page: https://docs.openclaw.ai/install/docker.md

  **Acceptance Criteria**:
  - [ ] Runbook is copy/paste runnable on linux host with podman + nix

  **QA Scenarios**:
  ```
  Scenario: Copy/paste runbook run command
    Tool: Bash
    Steps:
      1. Execute the runbook commands exactly
    Expected Result: gateway starts; logs appear in /logs
    Evidence: .sisyphus/evidence/task-8-runbook-run.txt
  ```

- [ ] 9. Smoke QA on Linux builder (native x86_64-linux)

  **What to do**:
  - On linux, run build→load→run smoke QA suite and capture evidence.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `developing-containers`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: F1
  - **Blocked By**: 6, 7, 8

  **Acceptance Criteria**:
  - [ ] All smoke QA scenarios pass on linux

- [ ] 10. Smoke QA on macOS via remote Linux builder

  **What to do**:
  - From macOS, build linux image via remote builder and run smoke QA (where podman runs).

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `managing-flakes`, `developing-containers`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: F1
  - **Blocked By**: 6, 8

  **Acceptance Criteria**:
  - [ ] macOS remote-builder build works; smoke run works

---

## Final Verification Wave

- [ ] F1. Smoke QA replay from clean slate (rootless podman, empty volumes) + evidence capture

---

## Commit Strategy
- Atomic commits; ask user before pushing.
- Suggested commits:
  1) `feat(openclaw): add nix-openclaw input + image scaffolding`
  2) `feat(openclaw): add openclaw-nix oci image + entrypoint + template`
  3) `docs(openclaw): add podman smoke-qa runbook`

---

## Success Criteria
- Image build is reproducible (fixed-input Nix; no network fetch at runtime)
- Rootless Podman `--userns=keep-id` works with writable `/config` and mounted `/state`/`/logs`
- Matrix+WhatsApp baseline config present and placeholders substituted

# Synapse → Dendrite cutover (same domain, fresh start)

## TL;DR
> **Summary**: Replace Synapse with Dendrite on `matrix.josevictor.me`, keep bridges, accept fresh start (no history/media preservation, user re-login). User explicitly accepts **no rollback + no restore path**.
> **Deliverables**:
> - New kubenix app: Dendrite monolith behind existing ingress host
> - Bridges (mautrix-whatsapp/discord/slack) pointed to Dendrite + compat flags
> - Synapse disabled (kept in repo as `_matrix*`)
> **Effort**: Medium
> **Parallel**: YES — 3 waves
> **Critical Path**: Define Dendrite config+app → move bridge secrets → disable Synapse → `make manifests` → deploy+verify bridges

## Context
### Original Request
- Read Dendrite docs; check if we can substitute current Synapse; check bridges; check seamless migration.

### Interview Summary
- Must keep same domain / MXID domain: `matrix.josevictor.me` (public) + `josevictor.me` (server_name).
- Bridges must work: mautrix-whatsapp/discord/slack.
- E2EE/device continuity **not required**; bridged rooms unencrypted OK.
- Fresh rooms OK; history and old MXC/media links can break.
- Users re-login OK.
- Clients: drop Element X (Dendrite lacks sliding sync); Element Web must work.
- Safety constraint: **proceed with risk** (no rollback target, no snapshot/restore path).

### Research Findings (repo)
- Synapse today: `modules/kubenix/apps/matrix.nix` (helm matrix-synapse), secrets+bridges: `modules/kubenix/apps/matrix-config.enc.nix`.
- Bridges deployments: `modules/kubenix/apps/mautrix-{whatsapp,discord,slack}.nix`.
- PostgreSQL DB bootstrap list: `config/kubernetes.nix` includes `synapse`, `mautrix_*`.
- OpenClaw points to Synapse: `modules/kubenix/apps/openclaw-config.enc.nix` contains `http://synapse-matrix-synapse:8008`.

### Metis Review (gaps addressed)
- Treat Dendrite media as filesystem/PVC (S3 not relied upon; user accepts old media breakage).
- No Synapse→Dendrite data migration attempted (fresh start).
- Bridges may need `--ignore-unsupported-server`; plan includes a hard gate: if bridge binary lacks the flag, abort migration.

## Work Objectives
### Core Objective
- Serve Matrix Client-Server API on `https://matrix.josevictor.me` via Dendrite; keep mautrix bridges functioning.

### Deliverables
- `modules/kubenix/apps/dendrite.nix`
- `modules/kubenix/apps/dendrite-config.enc.nix`
- `config/kubernetes.nix` updated: add `dendrite` DB
- Bridge deployments updated (command/args) to ignore unsupported server version (if available)
- Bridge configs updated to point homeserver at Dendrite service
- Synapse modules disabled by underscore rename (not deleted)
- OpenClaw Matrix homeserver URL updated

### Definition of Done (agent-verifiable)
- `make manifests` succeeds.
- Generated Dendrite manifest exists and targets `matrix.josevictor.me` ingress.
- Dendrite pod Running; `/_matrix/client/versions` returns JSON.
- All 3 bridge pods Running; logs show connected / no continuous retry loops.

### Must Have
- Appservice support enabled in Dendrite config with 3 registration YAMLs.
- Bridge configs point to Dendrite service.
- Federation disabled (match current).

### Must NOT Have (guardrails)
- Do NOT delete Synapse DB, Synapse PVC, or OBC/S3 bucket.
- Do NOT attempt to migrate Synapse DB/state/history/media.
- Do NOT enable Element X as a success criterion.

## Verification Strategy
> ZERO HUMAN INTERVENTION (agent executed)
- Test decision: tests-after (repo is infra; use `make manifests` + kubectl probes).
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.txt`

## Execution Strategy
### Parallel Execution Waves
- Wave 1 (config + new app): tasks 1-5
- Wave 2 (consumer updates + disable Synapse): tasks 6-9
- Wave 3 (generation + deploy verification): tasks 10-12

### Dependency Matrix (summary)
- 4 (dendrite-config secrets) blocks 8 (disable matrix-config)
- 3 (dendrite app) blocked by 4 (needs secret name + mounts)
- 10 (`make manifests`) blocked by 1-9

### Agent Dispatch Summary
- Wave 1: business-logic (nix wiring) + writing-nix-code skill
- Wave 2: business-logic + quick
- Wave 3: general (verification)

## TODOs

- [ ] 1. Confirm Dendrite container invocation + config path

  **What to do**:
  - Determine the correct command/args for `ghcr.io/element-hq/dendrite-monolith:<ver>` to run monolith with an explicit config file.
  - Hard requirement: executor must produce the exact command used in the final manifest (no guessing).

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 3 | Blocked By: []

  **References**:
  - Dendrite image/version decision from docs research (pin version)
  - Repo pattern for release submodule: `modules/kubenix/apps/ntfy.nix`

  **Acceptance Criteria**:
  - [ ] Evidence file contains chosen command + proof (e.g., `podman run --rm ... --help` output snippet): `.sisyphus/evidence/task-1-dendrite-command.txt`

  **QA Scenarios**:
  ```
  Scenario: Confirm monolith entrypoint/flags
    Tool: Bash
    Steps:
      - podman run --rm ghcr.io/element-hq/dendrite-monolith:<tag> --help
      - (if needed) podman run --rm ... <binary> --help
    Expected:
      - Clear, reproducible command to run server with config path
    Evidence: .sisyphus/evidence/task-1-dendrite-command.txt
  ```

  **Commit**: NO

- [ ] 2. Add Postgres database name(s) for Dendrite

  **What to do**:
  - Update `config/kubernetes.nix` `databases.postgres` list to include `"dendrite"`.
  - Do not remove existing DBs.

  **Must NOT do**:
  - Do not rename `synapse` DB.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 10 | Blocked By: []

  **References**:
  - `config/kubernetes.nix: databases.postgres`
  - `modules/kubenix/apps/postgresql-18.nix` (bootstrap uses that list)

  **Acceptance Criteria**:
  - [ ] `config/kubernetes.nix` contains `dendrite` in `databases.postgres`

  **QA Scenarios**:
  ```
  Scenario: Nix manifest generation sees new DB
    Tool: Bash
    Steps:
      - git add config/kubernetes.nix
      - make manifests
    Expected:
      - make manifests succeeds
    Evidence: .sisyphus/evidence/task-2-db-added.txt
  ```

  **Commit**: YES | Message: `chore(db): add dendrite database` | Files: `config/kubernetes.nix`

- [ ] 3. Add Dendrite secrets keys (SOPS source)

  **What to do**:
  - Add a new secret key in `secrets/k8s-secrets.enc.yaml`:
    - `dendrite_registration_shared_secret`
  - Use project rule: **only** `sops --set` (no decrypt/edit/re-encrypt).

  **Must NOT do**:
  - Do not add placeholders.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4 | Blocked By: []

  **References**:
  - Rule: `.docs/rules.md` (“Use sops --set to add keys”)
  - Existing mautrix token keys already present in `secrets/k8s-secrets.enc.yaml`

  **Acceptance Criteria**:
  - [ ] `sops -d secrets/k8s-secrets.enc.yaml | grep dendrite_registration_shared_secret` returns a value

  **QA Scenarios**:
  ```
  Scenario: Add secret key safely
    Tool: Bash
    Steps:
      - sops --set '["dendrite_registration_shared_secret"] "<generated>"' secrets/k8s-secrets.enc.yaml
      - sops -d secrets/k8s-secrets.enc.yaml | grep dendrite_registration_shared_secret
    Expected:
      - Key exists and decrypts cleanly
    Evidence: .sisyphus/evidence/task-3-sops-set.txt
  ```

  **Commit**: YES | Message: `chore(secrets): add dendrite registration secret` | Files: `secrets/k8s-secrets.enc.yaml`

- [ ] 4. Create `dendrite-config.enc.nix` (Dendrite + bridge secrets)

  **What to do**:
  - Add `modules/kubenix/apps/dendrite-config.enc.nix` defining:
    1) Secret `dendrite-config` containing `dendrite.yaml` (as `stringData."dendrite.yaml" = ...`).
    2) Secret(s) for bridge registrations + configs, replacing what currently lives in `matrix-config.enc.nix`:
       - `mautrix-whatsapp-registration`, `mautrix-whatsapp-config`
       - `mautrix-discord-registration`, `mautrix-discord-config`
       - `mautrix-slack-registration`, `mautrix-slack-config`
  - In each bridge `config.yaml`, change `homeserver.address` from Synapse svc to Dendrite svc (`http://dendrite:8008`).
  - For mautrix-whatsapp: set `appservice.ephemeral_events = false` (Dendrite lacks MSC2409).
  - Keep `homeserver.domain = "josevictor.me"`.
  - Do NOT change existing as_token/hs_token secret keys; reuse current ones.

  **Must NOT do**:
  - Do not reference `synapse-matrix-synapse` anywhere.

  **Recommended Agent Profile**:
  - Category: `business-logic`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 3,7,8,10 | Blocked By: 2,3

  **References**:
  - Current bridge secrets source: `modules/kubenix/apps/matrix-config.enc.nix`
  - Current bridge deployment mounts: `modules/kubenix/apps/mautrix-*.nix`
  - Dendrite appservice config list location: Dendrite docs (app_service_api.config_files)

  **Acceptance Criteria**:
  - [ ] New file exists: `modules/kubenix/apps/dendrite-config.enc.nix`
  - [ ] `grep -R "synapse-matrix-synapse" modules/kubenix/apps/dendrite-config.enc.nix` returns nothing

  **QA Scenarios**:
  ```
  Scenario: Secrets render and decrypt
    Tool: Bash
    Steps:
      - git add modules/kubenix/apps/dendrite-config.enc.nix
      - make manifests
      - sops -d .k8s/apps/dendrite-config.enc.yaml | grep -E 'dendrite\.yaml|mautrix-(whatsapp|discord|slack)'
      - sops -d .k8s/apps/dendrite-config.enc.yaml | grep -n 'dendrite:8008'
    Expected:
      - Secrets exist; homeserver.address points to dendrite
    Evidence: .sisyphus/evidence/task-4-dendrite-config.txt
  ```

  **Commit**: YES | Message: `feat(matrix): add dendrite config + bridge secrets` | Files: `modules/kubenix/apps/dendrite-config.enc.nix`

- [ ] 5. Create `dendrite.nix` (Dendrite app via release submodule)

  **What to do**:
  - Add `modules/kubenix/apps/dendrite.nix` using `submodules.instances.dendrite` + submodule `release`.
  - Service:
    - ClusterIP (override release default LoadBalancer)
    - Port 8008
  - Ingress:
    - Host: `matrix.josevictor.me`
    - className `cilium`, TLS `wildcard-tls`, issuer annotation like Synapse
  - Persistence:
    - Main PVC (rook-ceph-block, RWO) mounted at `/data` (includes media, jetstream, keys)
  - Mount secret file `dendrite-config` (from task 4) to `/etc/dendrite/dendrite.yaml` using app-template `persistence.<name>.type = "secret"` pattern (see `modules/kubenix/apps/prowlarr.nix`).
  - Add init container (or command wrapper) to:
    - create `/data` subdirs
    - generate private key if missing (per task 1 command)
    - set permissions
  - Set Dendrite image (pin tag+digest).

  **Must NOT do**:
  - Do not enable federation.

  **Recommended Agent Profile**:
  - Category: `business-logic`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 10,11,12 | Blocked By: 1,4

  **References**:
  - Release pattern: `modules/kubenix/apps/ntfy.nix`
  - Secret mount pattern: `modules/kubenix/apps/prowlarr.nix` (`persistence.*.type = "secret"`)
  - Current ingress host: `modules/kubenix/apps/matrix.nix`
  - LoadBalancer service IP map entry exists: `config/kubernetes.nix` (`matrix`)

  **Acceptance Criteria**:
  - [ ] `modules/kubenix/apps/dendrite.nix` exists
  - [ ] `make manifests` produces `.k8s/apps/dendrite.yaml`
  - [ ] `.k8s/apps/dendrite.yaml` contains ingress host `matrix.josevictor.me`

  **QA Scenarios**:
  ```
  Scenario: Manifest contains correct host/service
    Tool: Bash
    Steps:
      - git add modules/kubenix/apps/dendrite.nix
      - make manifests
      - grep -R "host: matrix.josevictor.me" -n .k8s/apps/dendrite.yaml
      - grep -R "containerPort: 8008" -n .k8s/apps/dendrite.yaml
    Expected:
      - Ingress + port correct
    Evidence: .sisyphus/evidence/task-5-dendrite-manifest.txt
  ```

  **Commit**: YES | Message: `feat(matrix): deploy dendrite homeserver` | Files: `modules/kubenix/apps/dendrite.nix`

- [ ] 6. Add bridge compat gate + update bridge deployments if supported

  **What to do**:
  - Determine if each bridge supports `--ignore-unsupported-server`.
  - If supported: update `modules/kubenix/apps/mautrix-{whatsapp,discord,slack}.nix` to run the bridge with that flag.
  - If NOT supported: **abort the migration** (do not proceed to task 8+).

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 10,11,12 | Blocked By: 5

  **References**:
  - Bridge deployments: `modules/kubenix/apps/mautrix-*.nix`

  **Acceptance Criteria**:
  - [ ] Evidence shows each image `--help` contains flag OR explicit abort recorded: `.sisyphus/evidence/task-6-bridge-flag.txt`

  **QA Scenarios**:
  ```
  Scenario: Verify flag exists in images
    Tool: Bash
    Steps:
      - podman run --rm dock.mau.dev/mautrix/whatsapp:v26.01 --help | grep -i unsupported || true
      - podman run --rm dock.mau.dev/mautrix/discord:v0.7.3 --help | grep -i unsupported || true
      - podman run --rm dock.mau.dev/mautrix/slack:latest --help | grep -i unsupported || true
    Expected:
      - Either all have flag, or migration aborted
    Evidence: .sisyphus/evidence/task-6-bridge-flag.txt
  ```

  **Commit**: YES | Message: `fix(matrix): bridge compat with dendrite` | Files: `modules/kubenix/apps/mautrix-*.nix`

- [ ] 7. Update OpenClaw Matrix homeserver URL

  **What to do**:
  - In `modules/kubenix/apps/openclaw-config.enc.nix`, replace all `http://synapse-matrix-synapse:8008` with `http://dendrite:8008`.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 10,11 | Blocked By: 5

  **References**:
  - Matches at lines near: `openclaw-config.enc.nix` (grep `synapse-matrix-synapse`)

  **Acceptance Criteria**:
  - [ ] `grep -n "synapse-matrix-synapse" modules/kubenix/apps/openclaw-config.enc.nix` returns nothing

  **QA Scenarios**:
  ```
  Scenario: Rendered secret points to dendrite
    Tool: Bash
    Steps:
      - git add modules/kubenix/apps/openclaw-config.enc.nix
      - make manifests
      - sops -d .k8s/apps/openclaw-config.enc.yaml | grep -n "dendrite:8008"
    Expected:
      - Dendrite URL present
    Evidence: .sisyphus/evidence/task-7-openclaw-dendrite.txt
  ```

  **Commit**: YES | Message: `chore(openclaw): point matrix to dendrite` | Files: `modules/kubenix/apps/openclaw-config.enc.nix`

- [ ] 8. Disable Synapse modules (keep for reference)

  **What to do**:
  - Rename:
    - `modules/kubenix/apps/matrix.nix` → `modules/kubenix/apps/_matrix.nix`
    - `modules/kubenix/apps/matrix-config.enc.nix` → `modules/kubenix/apps/_matrix-config.enc.nix`
  - Ensure all secrets needed for bridges now exist in `dendrite-config.enc.nix` (task 4), otherwise bridges will break.

  **Must NOT do**:
  - Do not delete the files; only disable.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10,11,12 | Blocked By: 4,5

  **References**:
  - Kubenix ignore rule: underscore-prefixed files are disabled (`.docs/rules.md`)

  **Acceptance Criteria**:
  - [ ] `make manifests` no longer generates `.k8s/apps/matrix.yaml` (or Flux no longer deploys Synapse resources)

  **QA Scenarios**:
  ```
  Scenario: Synapse manifests disappear
    Tool: Bash
    Steps:
      - git mv modules/kubenix/apps/matrix.nix modules/kubenix/apps/_matrix.nix
      - git mv modules/kubenix/apps/matrix-config.enc.nix modules/kubenix/apps/_matrix-config.enc.nix
      - make manifests
      - test ! -f .k8s/apps/matrix.yaml || true
    Expected:
      - Synapse app no longer rendered
    Evidence: .sisyphus/evidence/task-8-disable-synapse.txt
  ```

  **Commit**: YES | Message: `chore(matrix): disable synapse modules` | Files: `modules/kubenix/apps/_matrix.nix`, `modules/kubenix/apps/_matrix-config.enc.nix`

- [ ] 9. Repository-wide sanity: remove Synapse service dependencies

  **What to do**:
  - Search for `synapse-matrix-synapse` and replace with `dendrite` where appropriate.
  - Hard gate: after changes, only `_matrix*` files may reference Synapse.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 7,8

  **Acceptance Criteria**:
  - [ ] `grep -R "synapse-matrix-synapse" -n modules/kubenix/apps | grep -v "_matrix"` returns nothing

  **QA Scenarios**:
  ```
  Scenario: No dangling synapse references
    Tool: Bash
    Steps:
      - grep -R "synapse-matrix-synapse" -n modules/kubenix/apps | tee .sisyphus/evidence/task-9-synapse-refs.txt
    Expected:
      - Only _matrix* hits (or zero)
    Evidence: .sisyphus/evidence/task-9-synapse-refs.txt
  ```

  **Commit**: YES | Message: `chore(matrix): remove synapse service refs` | Files: (as needed)

- [ ] 10. Generate manifests + validate rendered YAML

  **What to do**:
  - Stage all new files (flake uses git state).
  - Run `make manifests`.
  - Validate:
    - Dendrite ingress host is `matrix.josevictor.me`
    - Dendrite uses ClusterIP
    - Dendrite config secret exists and contains appservice list
    - Bridge config secrets reference `http://dendrite:8008`

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 11,12 | Blocked By: 1-9

  **Acceptance Criteria**:
  - [ ] `make manifests` exits 0
  - [ ] `sops -d .k8s/apps/dendrite-config.enc.yaml | grep app_service_api` succeeds

  **QA Scenarios**:
  ```
  Scenario: Full pipeline render
    Tool: Bash
    Steps:
      - git status
      - make manifests
      - grep -R "host: matrix.josevictor.me" -n .k8s/apps/dendrite.yaml
      - grep -R "type: ClusterIP" -n .k8s/apps/dendrite.yaml
      - sops -d .k8s/apps/dendrite-config.enc.yaml | grep -n "app_service_api"
      - sops -d .k8s/apps/dendrite-config.enc.yaml | grep -n "dendrite:8008"
    Expected:
      - All checks pass
    Evidence: .sisyphus/evidence/task-10-manifests.txt
  ```

  **Commit**: NO

- [ ] 11. Deploy via Flux and verify Dendrite API

  **What to do**:
  - Commit/push changes (per repo process) and reconcile Flux.
  - Verify Dendrite pod running and responds.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 12 | Blocked By: 10

  **References**:
  - Namespace: `apps` (from `config/kubernetes.nix`)

  **Acceptance Criteria**:
  - [ ] `kubectl get pods -n apps | grep dendrite` shows Running
  - [ ] `kubectl exec -n apps deploy/dendrite -- wget -qO- http://localhost:8008/_matrix/client/versions` returns JSON

  **QA Scenarios**:
  ```
  Scenario: Dendrite health
    Tool: Bash
    Steps:
      - kubectl get pods -n apps | grep -E "dendrite|mautrix" || true
      - kubectl logs -n apps deploy/dendrite --tail=200
      - kubectl exec -n apps deploy/dendrite -- wget -qO- http://localhost:8008/_matrix/client/versions
    Expected:
      - No crashloop; versions endpoint responds
    Evidence: .sisyphus/evidence/task-11-dendrite-live.txt
  ```

  **Commit**: NO

- [ ] 12. Verify bridges connect + basic message flow

  **What to do**:
  - Ensure bridge pods are Running and not stuck on sync/auth.
  - Create/ensure bridge bot users exist (bridge should do it).
  - Validate message send path from bridge to Matrix:
    - Use bridge admin commands or logs to confirm a portal room is created.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: 11

  **Acceptance Criteria**:
  - [ ] `kubectl logs -n apps deploy/mautrix-whatsapp --tail=200` contains no repeated fatal errors
  - [ ] Same for discord + slack

  **QA Scenarios**:
  ```
  Scenario: Bridge liveness
    Tool: Bash
    Steps:
      - kubectl get pods -n apps -l app=mautrix-whatsapp
      - kubectl logs -n apps deploy/mautrix-whatsapp --tail=200
      - kubectl logs -n apps deploy/mautrix-discord --tail=200
      - kubectl logs -n apps deploy/mautrix-slack --tail=200
    Expected:
      - Bridges start and stay running; no auth/connection loops
    Evidence: .sisyphus/evidence/task-12-bridges-live.txt
  ```

  **Commit**: NO

## Final Verification Wave (MANDATORY)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (Element Web login)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- 1 commit per TODO where `Commit: YES` after user approval; otherwise batch commits only if requested.

## Success Criteria
- Dendrite serves `matrix.josevictor.me` and Element Web can log in.
- Bridges run and do not error-loop.
- No remaining non-underscore references to Synapse service.

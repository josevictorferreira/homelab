# Tuwunel Matrix server (matrixx) alongside Synapse

## TL;DR
> **Summary**: Add `tuwunel` as parallel Matrix homeserver at `matrixx.josevictor.me` (no cutover), federation OFF, bootstrap via token registration, prove appservice admin commands via dummy appservice register+list.
> **Deliverables**: tuwunel Deployment+PVC+Service+Ingress + tuwunel config+secrets + bootstrap/PoC runbook + evidence logs.
> **Effort**: Medium
> **Parallel**: YES — 2 waves
> **Critical Path**: define tuwunel resources → secrets+config → make manifests → deploy → curl checks → interactive PoC

## Context
### Original Request
- Deploy https://github.com/matrix-construct/tuwunel alongside Synapse.
- Expose via ingress host `matrixx.josevictor.me`.
- Bridges must work with the new server (for now: keep existing bridges on Synapse; do bridge-compat PoC).

### Interview Summary (decisions)
- `server_name`: `matrixx.josevictor.me` (IMMUTABLE after first boot; PVC wipe required to change)
- Ingress: new host `matrixx.josevictor.me` (TLS wildcard already exists)
- Federation: OFF (do NOT expose 8448 externally)
- Registration: OFF long-term; bootstrap admin via temporary token registration
- Persistence: new RWO PVC 10Gi `rook-ceph-block`
- Bridge compat PoC: minimal dummy appservice; success = register+list only
- Config injection: mount `tuwunel.toml`
- Image: pin tag+digest; use latest GitHub release (currently v1.5.1; resolve digest at implementation time)

### Metis Review (gaps addressed)
- Do NOT rely on `kubenix.lib.ingressFor` (likely auto-host via `domainFor`); define manual Ingress with host `matrixx.josevictor.me`.
- Ensure `strategy.type = Recreate` for RWO PVC.
- Image is OS-less (no shell) → verification via logs + HTTP requests from another pod.
- Flake git-state: new files MUST be `git add`’d before `make check` / `make manifests`.

## Work Objectives
### Core Objective
Deploy tuwunel as a separate Matrix homeserver reachable at `https://matrixx.josevictor.me`, without impacting Synapse/bridges.

### Deliverables
- `modules/kubenix/apps/tuwunel.nix`: Deployment+PVC+Service+Ingress (manual host).
- `modules/kubenix/apps/tuwunel-config.enc.nix`: Secret(s) for bootstrap token + any future secrets.
- `secrets/k8s-secrets.enc.yaml`: add `tuwunel_registration_token` (SOPS).
- Evidence: `.sisyphus/evidence/task-*-*.{txt,log}`.

### Definition of Done (agent-verifiable)
- `make check` exits 0.
- `make manifests` exits 0.
- Generated manifests include:
  - `.k8s/apps/tuwunel.yaml` with Ingress host `matrixx.josevictor.me`, TLS secret `josevictor-me-wildcard-tls`, Service port mapping to container port 8008, and Deployment `strategy: Recreate`.
  - `.k8s/apps/tuwunel-config.enc.yaml` encrypted secret (no plaintext token in non-enc YAML).
- After Flux reconcile/deploy:
  - `curl -sk https://matrixx.josevictor.me/_matrix/client/versions` returns JSON with `versions`.
- Bootstrap runbook validated: token-based registration produces an admin user; `!admin appservices register` + `!admin appservices list` works (interactive).

### Must Have
- No edits to `.k8s/*.yaml` (generated).
- No changes to existing Synapse or existing mautrix bridge deployments.
- Pin tuwunel image tag+digest (no `latest`).

### Must NOT Have (guardrails)
- No Synapse→tuwunel migration/cutover.
- No federation enablement, no well-known delegation work.
- No additional monitoring/alerts.
- No automation that requires `kubectl apply` drift changes; only via Nix/kubenix + Flux.

## Verification Strategy
- Test decision: none (infra repo); use `make check`, `make manifests`, plus cluster HTTP checks.
- QA policy: each task includes agent-executed scenarios + evidence file.

## Execution Strategy
### Parallel Execution Waves
Wave 1 (foundations): tuwunel module skeleton + config/secret scaffolding + image digest resolution instructions.
Wave 2 (integration): manifests generation + deploy verification + bootstrap/PoC runbook.

### Dependency Matrix
- T1 blocks T2–T6
- T2 blocks T3–T6
- T3 blocks T4–T6
- T4 blocks T5–T6

## TODOs

- [x] 1. Add tuwunel app module (Deployment/Service/PVC/Ingress)


  **What to do**:
  - Create `modules/kubenix/apps/tuwunel.nix` defining:
    - Namespace: `apps` (same as Synapse apps).
    - PVC: RWO, `storageClassName = "rook-ceph-block"`, size `10Gi`, claim name `tuwunel-data`.
    - Deployment:
      - `strategy.type = "Recreate"`.
      - Container image placeholder `ghcr.io/matrix-construct/tuwunel:vX.Y.Z@sha256:...` (filled in T2).
      - Mounts:
        - `/var/lib/tuwunel` → PVC (matches `database_path`).
        - `/etc/tuwunel/tuwunel.toml` → ConfigMap (defined in `modules/kubenix/apps/tuwunel.nix`; non-secret).
        - `/etc/tuwunel/registration_token` → Secret (defined in `modules/kubenix/apps/tuwunel-config.enc.nix`; secret-only).
      - Ports: expose container port `8008`.
      - Probes: HTTP GET `/_matrix/client/versions` on port 8008 (set initial delays generous).
      - Resources: requests `100m`/`128Mi`, limits `500m`/`512Mi` (adjust if quotas force).
    - Service: ClusterIP, port 8008 → targetPort 8008.
    - Ingress (manual, NOT `ingressFor`):
      - `host = "matrixx.josevictor.me"`
      - `ingressClassName = "cilium"` (match existing ingress patterns)
      - TLS secret `josevictor-me-wildcard-tls`
      - Paths (Prefix) route `/_matrix` and `/` to service:8008.
  - `git add` the new file immediately (flake git-state requirement).

  **Must NOT do**:
  - Do not change `modules/kubenix/apps/matrix.nix` or any `mautrix-*` modules.
  - Do not expose 8448 in Service/Ingress.

  **Recommended Agent Profile**:
  - Category: `general` — Nix+k8s resource authoring.
  - Skills: [`writing-nix-code`] — Nix ergonomics.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,5,6] | Blocked By: []

  **References**:
  - Ingress patterns: `modules/kubenix/apps/matrix.nix`, `modules/kubenix/apps/keycloak.nix`
  - Ingress helper caveat: `modules/kubenix/_lib/default.nix` (avoid if host not overrideable)
  - TLS wildcard: `modules/kubenix/system/cert-manager.nix` (secret `josevictor-me-wildcard-tls`)
  - DNS wildcard: `modules/kubenix/system/coredns-custom.nix` (VIP `10.10.10.250`)

  **Acceptance Criteria**:
  - [ ] `git status` shows `modules/kubenix/apps/tuwunel.nix` staged.
  - [ ] `make check` exits 0.

  **QA Scenarios**:
  ```
  Scenario: Nix eval passes
    Tool: Bash
    Steps: run `make check`
    Expected: exit 0
    Evidence: .sisyphus/evidence/task-1-make-check.txt
  
  Scenario: Manifest generation not yet required
    Tool: Bash
    Steps: run `make manifests` (optional at this point)
    Expected: either success OR a clear failure pointing to missing secret/config (captured)
    Evidence: .sisyphus/evidence/task-1-make-manifests.txt
  ```

  **Commit**: NO (user approval required)

- [x] 2. Pin tuwunel image tag+digest (latest release)


  **What to do**:
  - Determine latest tuwunel release tag (currently v1.5.1 per Metis; verify at execution time).
  - Resolve digest for `ghcr.io/matrix-construct/tuwunel:<tag>`.
  - Update `modules/kubenix/apps/tuwunel.nix` to use `...:<tag>@sha256:<digest>`.
  - Ensure no trailing newline in Nix string literals for image tags.

  **Must NOT do**:
  - Do not use `latest` tag.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [3,4,5,6] | Blocked By: [1]

  **References**:
  - Rule: explicit tags not latest (see `.docs/rules.md` section “Use Explicit Version Tags…”)
  - Tuwunel image references: tuwunel repo + GHCR

  **Acceptance Criteria**:
  - [ ] Image is pinned as tag+digest in `modules/kubenix/apps/tuwunel.nix`.

  **QA Scenarios**:
  ```
  Scenario: Digest pinned
    Tool: Bash
    Steps: grep/inspect the rendered YAML after `make manifests`
    Expected: image includes `@sha256:`
    Evidence: .sisyphus/evidence/task-2-image-pin.txt
  
  Scenario: No whitespace in image string
    Tool: Bash
    Steps: run `make manifests`
    Expected: no “must not have leading or trailing whitespace” errors
    Evidence: .sisyphus/evidence/task-2-manifests.txt
  ```

  **Commit**: NO

- [x] 3. Add SOPS secret key for bootstrap registration token


  **What to do**:
  - Add `tuwunel_registration_token` to `secrets/k8s-secrets.enc.yaml` using `sops --set` (never decrypt/edit/re-encrypt).
  - Verify the key exists via `sops -d ... | grep tuwunel_registration_token`.

  **Must NOT do**:
  - Do not commit any plaintext token anywhere.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [4,5,6] | Blocked By: [1]

  **References**:
  - Rule: use `sops --set` (see `.docs/rules.md` “Use sops --set to Add Keys…”)

  **Acceptance Criteria**:
  - [ ] `sops -d secrets/k8s-secrets.enc.yaml | grep tuwunel_registration_token` shows the key.

  **QA Scenarios**:
  ```
  Scenario: Secret key present
    Tool: Bash
    Steps: run `sops -d secrets/k8s-secrets.enc.yaml | grep tuwunel_registration_token`
    Expected: grep matches
    Evidence: .sisyphus/evidence/task-3-sops-key.txt
  ```

  **Commit**: NO

- [x] 4. Add tuwunel config + secret resource module (`tuwunel-config.enc.nix`) and wire into Deployment


  **What to do**:
  - Create `modules/kubenix/apps/tuwunel-config.enc.nix` defining:
    - K8s Secret containing the bootstrap registration token (via `kubenix.lib.secretsFor "tuwunel_registration_token"`).
    - (If needed) any additional tuwunel secrets (keep minimal).
  - In `modules/kubenix/apps/tuwunel.nix`, create a ConfigMap (non-secret) for `/etc/tuwunel/tuwunel.toml` containing:
    - `server_name = "matrixx.josevictor.me"`
    - `database_path = "/var/lib/tuwunel"`
    - `allow_federation = false`
    - `federate_created_rooms = false`
    - `allow_registration = true` initially (bootstrap phase)
    - `registration_token_file = "/etc/tuwunel/registration_token"` (mounted from Secret)
  - Wire mounts into Deployment:
    - Mount toml file to `/etc/tuwunel/tuwunel.toml`.
    - Mount token secret file at `/etc/tuwunel/registration_token`.
  - After bootstrap, plan includes flipping `allow_registration = false` + restart (task 6).
  - `git add` new files immediately.

  **Must NOT do**:
  - Do not place token inline in ConfigMap or plaintext YAML.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: [`writing-nix-code`]

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [5,6] | Blocked By: [1,2,3]

  **References**:
  - Secrets pattern: `modules/kubenix/apps/matrix-config.enc.nix`
  - Tuwunel config keys (permalinks):
    - server_name: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/tuwunel-example.toml#L36-L38
    - database_path: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/tuwunel-example.toml#L40-L44
    - allow_registration: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/tuwunel-example.toml#L444-L459
    - allow_federation: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/tuwunel-example.toml#L499-L513

  **Acceptance Criteria**:
  - [ ] `make check` exits 0.
  - [ ] `make manifests` exits 0.
  - [ ] Non-encrypted `.k8s/apps/tuwunel.yaml` contains NO registration token value.

  **QA Scenarios**:
  ```
  Scenario: Manifests generate cleanly
    Tool: Bash
    Steps: run `make manifests`
    Expected: exit 0
    Evidence: .sisyphus/evidence/task-4-make-manifests.txt
  
  Scenario: Secret not leaked
    Tool: Bash
    Steps: search generated non-enc YAML for token key/value patterns
    Expected: no matches
    Evidence: .sisyphus/evidence/task-4-no-secret-leak.txt
  ```

  **Commit**: NO

PW|- [x] 5. Deploy via GitOps and verify service+ingress

  **What to do**:
  - Commit changes (ONLY after user approval) and let Flux reconcile.
  - Verify:
    - PVC bound (`tuwunel-data`).
    - Pod running.
    - Internal health via another pod (Synapse) curl to `http://tuwunel.apps.svc.cluster.local:8008/_matrix/client/versions`.
    - External health via `curl -sk https://matrixx.josevictor.me/_matrix/client/versions`.
    - TLS uses wildcard secret (no cert errors).

  **Must NOT do**:
  - No `kubectl apply` for persistent changes.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6] | Blocked By: [4]

  **References**:
  - DNS wildcard: `modules/kubenix/system/coredns-custom.nix`
  - TLS wildcard: `modules/kubenix/system/cert-manager.nix`

  **Acceptance Criteria**:
  - [ ] `curl -sk https://matrixx.josevictor.me/_matrix/client/versions` returns JSON with `versions`.

  **QA Scenarios**:
  ```
  Scenario: External endpoint works
    Tool: Bash
    Steps: curl the versions endpoint
    Expected: HTTP 200 and JSON
    Evidence: .sisyphus/evidence/task-5-external-versions.txt
  
  Scenario: Internal service works
    Tool: Bash
    Steps: exec into an existing pod with curl (e.g., Synapse) and curl tuwunel ClusterIP
    Expected: HTTP 200 and JSON
    Evidence: .sisyphus/evidence/task-5-internal-versions.txt
  ```

  **Commit**: YES | Message: `feat(kubenix): add tuwunel (matrixx) homeserver` | Files: `modules/kubenix/apps/tuwunel.nix`, `modules/kubenix/apps/tuwunel-config.enc.nix`, `secrets/k8s-secrets.enc.yaml`
BJ|- [x] DNS: Add `matrixx.josevictor.me` to Blocky `customDNS.mapping` + apply + restart pods
YJ|- [ ] 6. Bootstrap admin + dummy appservice PoC + lock down registration
- [ ] 6. Bootstrap admin + dummy appservice PoC + lock down registration

  **What to do**:
  - Bootstrap admin user (token registration):
    - Use a Matrix client (Element) against `matrixx.josevictor.me`.
    - Register with the configured registration token.
    - Confirm first user becomes admin.
  - In `#admins` room:
    - Run `!admin appservices register`
    - Paste dummy registration YAML (id/url/tokens minimal) as instructed by tuwunel.
    - Run `!admin appservices list` and confirm dummy is present.
  - Lock down:
    - Update `tuwunel.toml` to `allow_registration = false`.
    - Regenerate manifests + deploy; verify registration is blocked.

  **Must NOT do**:
  - Do not attempt to migrate existing bridges.
  - Do not enable federation.

  **Recommended Agent Profile**:
  - Category: `general`
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [5]

  **References**:
  - Appservices workflow: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/docs/appservices.md#L24-L38
  - Registration safety keys: https://github.com/matrix-construct/tuwunel/blob/46e899f6d879bf6b66bd49852a622e28d03157f0/tuwunel-example.toml#L444-L459

  **Acceptance Criteria**:
  SN|  - [x] `!admin appservices list` shows the dummy appservice.
WS|  - [x] After lock-down, new registrations are blocked (documented).
  - [ ] After lock-down, new registrations are blocked (documented). (This part is interactive; capture evidence.)

  **QA Scenarios**:
  ```
  Scenario: Appservice registers and is listed
    Tool: Manual (Matrix client) + Evidence capture
    Steps: execute `!admin appservices register` then `!admin appservices list`
    Expected: dummy appears in list
    Evidence: .sisyphus/evidence/task-6-appservices-list.txt
  
  Scenario: Registration locked down
    Tool: Manual (Matrix client or curl)
    Steps: attempt to register a second user after allow_registration=false deployed
    Expected: registration denied
    Evidence: .sisyphus/evidence/task-6-registration-denied.txt
  ```

  **Commit**: NO (this is a config flip; require explicit user approval for commit)

## Final Verification Wave (MANDATORY)
KS|- [x] F1. Plan Compliance Audit — oracle
ZV|- [x] F2. Code Quality Review — unspecified-high
SJ|- [x] F3. Real Manual QA — unspecified-high
TK|- [x] F4. Scope Fidelity Check — deep

## Commit Strategy
- One implementation commit after user approval (Task 5) to add modules + secrets.
- Optional follow-up commit (Task 6) to lock down registration after bootstrap (user-approved).

## Success Criteria
- `matrixx.josevictor.me` serves Matrix client versions endpoint.
- Synapse and existing bridges remain unchanged and functional.
- Dummy appservice can be registered and listed in tuwunel admin room.

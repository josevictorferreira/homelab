# Dendrite parallel deploy on matrixx (keep Synapse live)

## TL;DR
> **Summary**: Keep Synapse on `matrix.josevictor.me` unchanged; deploy Dendrite monolith in parallel on `matrixx.josevictor.me` (LAN-only) for testing.
> **Deliverables**:
> - New kubenix app: `matrixx` (Dendrite) behind Cilium ingress + wildcard TLS
> - New Postgres DB: `dendrite`
> - 1 reproducible test account creation Job (registration stays disabled)
> **Effort**: Medium
> **Parallel**: YES — 3 waves
> **Critical Path**: Decide Dendrite CLI+config → add DB+DNS mapping+secrets → add Nix modules → `make manifests` → deploy → verify Synapse unaffected

## Context
### Original Request
- Evaluate Dendrite vs Synapse; then user chose: keep Synapse running, deploy Dendrite separately on `matrixx.josevictor.me` for now.

### Interview Summary (final decisions)
- Synapse stays authoritative + running on `matrix.josevictor.me` (no cutover).
- Dendrite public host: `matrixx.josevictor.me`.
- Dendrite `server_name`: `josevictor.me` (same MXID domain as Synapse).
- `/.well-known/matrix/*` remains pointing to Synapse only.
- Dendrite registration disabled.
- LAN-only exposure (no Cloudflare changes).
- Create 1 Dendrite test user for Element Web login.

### Research Findings (repo)
- Synapse ingress pattern: `modules/kubenix/apps/matrix.nix` (Cilium ingress + `wildcard-tls`, ClusterIP:8008).
- Raw Deployment+Service pattern: `modules/kubenix/apps/flaresolverr.nix`.
- Postgres DB bootstrap consumes `config/kubernetes.nix` `databases.postgres`: `modules/kubenix/apps/postgresql-18.nix` (ConfigMap + Job).
- Internal DNS mapping: Blocky builds `customDNS` from `homelab.kubernetes.loadBalancer.services` and maps `${service}.${homelab.domain}` → `homelab.kubernetes.loadBalancer.address` (`modules/kubenix/apps/blocky-config.enc.nix`).

### Metis Review (gaps addressed)
- Shared `server_name` split-brain is risky; treat Dendrite as **LAN-only + non-federating + undiscoverable** (no well-known).
- Prefer raw K8s resources (no Helm chart dependency).
- Ensure service name aligns with desired DNS (`matrixx`), otherwise Blocky mapping won’t produce `matrixx.josevictor.me`.

### Oracle Review (gaps addressed)
- Shared `server_name` is only acceptable for local testing if federation is effectively off and discovery stays on Synapse.
- Create test user via idempotent Kubernetes Job calling Dendrite CLI; password in SOPS.
- Add ingress/cluster guardrails so traffic cannot reach Dendrite via `matrix.josevictor.me`.

## Work Objectives
### Core Objective
- Run a Dendrite homeserver at `https://matrixx.josevictor.me` without impacting Synapse (`https://matrix.josevictor.me`).

### Definition of Done (agent-verifiable)
- `make manifests` succeeds.
- Synapse remains Running and `/_matrix/client/versions` still returns JSON.
- Dendrite deployment Running and `curl -k https://matrixx.josevictor.me/_matrix/client/versions` returns JSON.
- Dendrite registration remains disabled; test user exists and can log in from Element Web (agent-executed).

### Must Have
- Dendrite uses separate Postgres DB (`dendrite`) and separate PVC.
- Dendrite does NOT become discovery target for `josevictor.me` (no `.well-known` change).
- Dendrite does NOT expose federation port(s); do not publish 8448.
- Bridges remain pointed at Synapse (no bridge changes).

### Must NOT Have (guardrails)
- Do NOT modify `modules/kubenix/apps/matrix.nix` or `matrix-config.enc.nix`.
- Do NOT touch Synapse DB (`synapse`) or Synapse PVC.
- Do NOT enable federation on Dendrite.
- Do NOT add any routing where `matrix.josevictor.me` can hit Dendrite.

## Verification Strategy
> ZERO HUMAN INTERVENTION — agent executes all checks.
- Primary verification: `make manifests` + `kubectl` probes + `curl` from a pod.
- Evidence files: `.sisyphus/evidence/task-{N}-{slug}.txt`

## Execution Strategy
### Parallel Execution Waves
Wave 1 (discovery + prereqs): tasks 1–4
Wave 2 (Nix modules): tasks 5–9
Wave 3 (render + deploy + runtime verification): tasks 10–13

### Dependency Matrix (summary)
- 5/6 (secrets + config) blocked by 1–4
- 7 (deployment+ingress) blocked by 5/6
- 10+ (render/deploy/verify) blocked by 5–9

## TODOs
> Implementation + verification = ONE task.
> Executor MUST stage new files before `make manifests` (flake uses git state).

- [x] 1. Pin Dendrite image tag+digest + determine runtime command

  **What to do**:
  - Choose Dendrite monolith image tag (start w/ `ghcr.io/element-hq/dendrite-monolith:v0.15.2`).
  - Resolve + record image digest to pin (`@sha256:...`).
  - Determine exact command+args to run monolith with a config file at a known path.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 6,7 | Blocked By: []

  **References**:
  - Prior plan pattern for CLI discovery (podman `--help`).

  **Acceptance Criteria**:
  - [ ] Evidence contains: chosen image ref w/ digest + exact container command: `.sisyphus/evidence/task-1-dendrite-image-cmd.txt`

  **QA Scenarios**:
  ```
  Scenario: Determine CLI invocation
    Tool: Bash
    Steps:
      - podman pull ghcr.io/element-hq/dendrite-monolith:v0.15.2
      - podman inspect ghcr.io/element-hq/dendrite-monolith:v0.15.2 --format '{{.Digest}}'
      - podman run --rm ghcr.io/element-hq/dendrite-monolith:v0.15.2 --help || true
      - (if needed) podman run --rm --entrypoint sh ghcr.io/element-hq/dendrite-monolith:v0.15.2 -lc 'ls -la /usr/bin /bin | grep -i dendrite || true'
    Expected:
      - Clear command+flags to run with config file path
    Evidence: .sisyphus/evidence/task-1-dendrite-image-cmd.txt
  ```

  **Commit**: NO

- [x] 2. Decide Dendrite config shape (server_name, federation off, registration off)

  **What to do**:
  - Produce a minimal `dendrite.yaml` that:
    - Sets `global.server_name = josevictor.me`
    - Disables federation listeners / does not expose federation
    - Disables open registration
    - Configures Postgres connection to DB `dendrite` on `postgresql-18-hl.apps.svc.cluster.local:5432`

  **Must NOT do**:
  - Do not re-use Synapse signing key.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 6 | Blocked By: 1

  **Acceptance Criteria**:
  - [ ] Evidence file includes the full proposed `dendrite.yaml` content + sources: `.sisyphus/evidence/task-2-dendrite-yaml.txt`

  **QA Scenarios**:
  ```
  Scenario: Validate config keys exist
    Tool: Bash
    Steps:
      - (use container docs/help output; if available) generate example config then diff with minimal config
    Expected:
      - No unknown-key errors at runtime (validated later in task 12 logs)
    Evidence: .sisyphus/evidence/task-2-dendrite-yaml.txt
  ```

  **Commit**: NO

- [x] 3. Reserve internal DNS name `matrixx.josevictor.me`

  **What to do**:
  - Update `config/kubernetes.nix`:
    - Add `matrixx = "10.10.10.142";` under `loadBalancer.services` (pick next free after openclaw-nix=141).
    - Add `"dendrite"` to `databases.postgres` list.

  **References**:
  - DNS mapping mechanism: `modules/kubenix/apps/blocky-config.enc.nix` (`dnsHosts` uses `domainFor`).
  - DB bootstrap consumer: `modules/kubenix/apps/postgresql-18.nix` (`bootstrapDatabases`).

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 10 | Blocked By: []

  **Acceptance Criteria**:
  - [ ] `config/kubernetes.nix` contains `matrixx` mapping + `dendrite` DB entry

  **QA Scenarios**:
  ```
  Scenario: Flake sees changes
    Tool: Bash
    Steps:
      - git add config/kubernetes.nix
      - make manifests
    Expected:
      - make manifests succeeds
    Evidence: .sisyphus/evidence/task-3-kubernetes-nix.txt
  ```

  **Commit**: YES | Message: `chore(matrix): reserve matrixx dns + dendrite db` | Files: `config/kubernetes.nix`

- [x] 4. Add SOPS secret keys for Dendrite test user

  **What to do**:
  - Add new SOPS keys in `secrets/k8s-secrets.enc.yaml` using `sops --set` (project rule):
    - `dendrite_test_user_password`

  **Must NOT do**:
  - No placeholders.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 8,9 | Blocked By: []

  **References**:
  - `.docs/rules.md` (“Use `sops --set` to add keys”).

  **Acceptance Criteria**:
  - [ ] `sops -d secrets/k8s-secrets.enc.yaml | grep dendrite_test_user_password` returns a value

  **QA Scenarios**:
  ```
  Scenario: Add key safely
    Tool: Bash
    Steps:
      - sops --set '"[\"dendrite_test_user_password\"]" "<generated>"' secrets/k8s-secrets.enc.yaml
      - sops -d secrets/k8s-secrets.enc.yaml | grep dendrite_test_user_password
    Expected:
      - Key present + decrypts
    Evidence: .sisyphus/evidence/task-4-dendrite-secret.txt
  ```

  **Commit**: YES | Message: `chore(secrets): add dendrite test user password` | Files: `secrets/k8s-secrets.enc.yaml`

- [x] 5. Create `modules/kubenix/apps/matrixx-config.enc.nix` (Dendrite config + password)

  **What to do**:
  - Add `modules/kubenix/apps/matrixx-config.enc.nix` defining secret `matrixx-config` with:
    - `stringData."dendrite.yaml" = ...` (from task 2)
    - (optional) any other required config files
  - If the Dendrite config requires a DB password, use `kubenix.lib.secretsInlineFor` to inject values.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 7 | Blocked By: 1,2,4

  **References**:
  - Secrets pattern: `modules/kubenix/apps/matrix-config.enc.nix` (stringData + `toYamlStr`).

  **Acceptance Criteria**:
  - [ ] New file exists and contains `matrixx-config` secret
  - [ ] No references to `synapse-*` inside this file

  **QA Scenarios**:
  ```
  Scenario: Render encrypted secret
    Tool: Bash
    Steps:
      - git add modules/kubenix/apps/matrixx-config.enc.nix
      - make manifests
      - sops -d .k8s/apps/matrixx-config.enc.yaml | grep -n 'dendrite\.yaml'
    Expected:
      - Rendered encrypted secret contains dendrite.yaml
    Evidence: .sisyphus/evidence/task-5-matrixx-config.txt
  ```

  **Commit**: YES | Message: `feat(matrix): add matrixx dendrite config secret` | Files: `modules/kubenix/apps/matrixx-config.enc.nix`

- [x] 6. Create `modules/kubenix/apps/matrixx.nix` (Dendrite Deployment+Service+Ingress)

  **What to do**:
  - Create a raw-resource module (copy `flaresolverr.nix` structure) that defines:
    - Deployment `matrixx` running Dendrite monolith
    - ClusterIP Service `matrixx` port 8008 (name `http`)
    - Ingress for host `matrixx.josevictor.me` with TLS `wildcard-tls` and issuer annotation
    - Mount secret `matrixx-config` to `/etc/dendrite/dendrite.yaml` (path from task 1)
    - Add PVC (rook-ceph-block, RWO) for Dendrite state/media (mount path decided in task 1/2)
  - Ensure service name is exactly `matrixx` (matches Blocky domainFor and ingress host).

  **Must NOT do**:
  - Do not expose 8448 or any federation listener.
  - Do not use `kubenix.lib.serviceAnnotationFor` (no per-service LB needed).

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 10 | Blocked By: 1,5

  **References**:
  - Raw pattern: `modules/kubenix/apps/flaresolverr.nix`.
  - Ingress pattern: `modules/kubenix/apps/matrix.nix` (annotations + tls secret).
  - Helper ingress (optional): `modules/kubenix/_lib/default.nix` (`ingressFor`, `domainFor`).

  **Acceptance Criteria**:
  - [ ] `make manifests` creates `.k8s/apps/matrixx.yaml`
  - [ ] `.k8s/apps/matrixx.yaml` contains host `matrixx.josevictor.me` and backend service `matrixx`

  **QA Scenarios**:
  ```
  Scenario: Manifest sanity
    Tool: Bash
    Steps:
      - git add modules/kubenix/apps/matrixx.nix
      - make manifests
      - grep -R "host: matrixx.josevictor.me" -n .k8s/apps/matrixx.yaml
      - grep -R "name: matrixx" -n .k8s/apps/matrixx.yaml | head -n 20
    Expected:
      - Ingress host present; service name matches
    Evidence: .sisyphus/evidence/task-6-matrixx-manifest.txt
  ```

  **Commit**: YES | Message: `feat(matrix): deploy dendrite on matrixx` | Files: `modules/kubenix/apps/matrixx.nix`

- [x] 7. Add Dendrite test-user creation Job (idempotent)

  **What to do**:
  - Add a kubenix `resources.jobs.<name>` in `modules/kubenix/apps/matrixx.nix` (or separate `matrixx-user-job.nix`) that:
    - Runs after Dendrite is deployed (no strict ordering in GitOps; make it retry-safe)
    - Uses the same Dendrite image
    - Creates `@dendrite-test:josevictor.me` with password from SOPS key `dendrite_test_user_password`
    - Is idempotent: if user exists, exit 0
    - Uses `restartPolicy = "OnFailure"` and a short backoff

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 12,13 | Blocked By: 1,4,6

  **Acceptance Criteria**:
  - [ ] `make manifests` includes a Job resource for test-user creation

  **QA Scenarios**:
  ```
  Scenario: Job script idempotency
    Tool: Bash
    Steps:
      - make manifests
      - (after deploy) kubectl logs -n apps job/<jobname> --tail=200
    Expected:
      - Job completes successfully; re-run (if any) does not fail on user-exists
    Evidence: .sisyphus/evidence/task-7-testuser-job.txt
  ```

  **Commit**: YES | Message: `feat(matrix): add dendrite test user job` | Files: `modules/kubenix/apps/matrixx.nix` (or new file)

- [x] 8. Repo-wide guardrail: ensure no matrixx changes touch Synapse/bridges

  **What to do**:
  - Verify no edits to Synapse modules were made.
  - Verify bridges still point to Synapse service.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 5–7

  **Acceptance Criteria**:
  - [ ] `git diff --name-only` contains no Synapse/bridge files (except intended)

  **QA Scenarios**:
  ```
  Scenario: No Synapse/bridge edits
    Tool: Bash
    Steps:
      - git diff --name-only | tee .sisyphus/evidence/task-8-changed-files.txt
    Expected:
      - Only: config/kubernetes.nix, secrets/k8s-secrets.enc.yaml, modules/kubenix/apps/matrixx*.nix
    Evidence: .sisyphus/evidence/task-8-changed-files.txt
  ```

  **Commit**: NO

- [x] 9. Render pipeline gate: full `make manifests` from clean git stage

  **What to do**:
  - Stage all new files (flake uses git state).
  - Run `make manifests` and capture output.

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 10–13 | Blocked By: 3–8

  **Acceptance Criteria**:
  - [ ] `make manifests` exits 0

  **QA Scenarios**:
  ```
  Scenario: Full render
    Tool: Bash
    Steps:
      - git status
      - make manifests
    Expected:
      - Exit 0
    Evidence: .sisyphus/evidence/task-9-make-manifests.txt
  ```

  **Commit**: NO

- [ ] 10. Deploy via Flux (commit/push) and verify Dendrite is reachable

  **What to do**:
  - Commit/push per repo workflow.
  - Reconcile Flux.
  - Verify from inside cluster:
    - Dendrite pod Running
    - `/_matrix/client/versions` responds
    - Ingress responds on `matrixx.josevictor.me`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 11–13 | Blocked By: 9

  **Acceptance Criteria**:
  - [ ] `curl -sk https://matrixx.josevictor.me/_matrix/client/versions` returns JSON

  **QA Scenarios**:
  ```
  Scenario: Dendrite live
    Tool: Bash
    Steps:
      - kubectl get pods -n apps | grep matrixx
      - kubectl logs -n apps deploy/matrixx --tail=200
      - kubectl exec -n apps deploy/matrixx -- wget -qO- http://localhost:8008/_matrix/client/versions
      - curl -sk https://matrixx.josevictor.me/_matrix/client/versions
    Expected:
      - versions JSON both locally and via ingress
    Evidence: .sisyphus/evidence/task-10-dendrite-live.txt
  ```

  **Commit**: NO

- [ ] 11. Verify Synapse + bridges unaffected

  **What to do**:
  - Confirm Synapse still healthy.
  - Confirm mautrix pods are still Running.

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: 12–13 | Blocked By: 10

  **Acceptance Criteria**:
  - [ ] Synapse versions endpoint still works
  - [ ] Bridge pods Running (no crashloop)

  **QA Scenarios**:
  ```
  Scenario: Synapse not impacted
    Tool: Bash
    Steps:
      - kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- wget -qO- http://localhost:8008/_matrix/client/versions
      - kubectl get pods -n apps | grep -E 'mautrix-(whatsapp|discord|slack)'
    Expected:
      - Synapse responds; bridges present
    Evidence: .sisyphus/evidence/task-11-synapse-bridges-ok.txt
  ```

  **Commit**: NO

- [ ] 12. Verify Dendrite registration disabled + test user login works

  **What to do**:
  - Confirm registration endpoints do not allow signup.
  - Use Element Web (agent-executed via browser tools) to log in to `matrixx.josevictor.me` with `@dendrite-test:josevictor.me`.

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: 10,7

  **Acceptance Criteria**:
  - [ ] Login succeeds; can create a local room and send a message.

  **QA Scenarios**:
  ```
  Scenario: Element Web login to matrixx
    Tool: browser-debug-tools
    Steps:
      - Open Element Web, choose “Custom server”, enter https://matrixx.josevictor.me
      - Login as @dendrite-test:josevictor.me with SOPS password
      - Create local room, send message “matrixx smoke”
    Expected:
      - Login OK; message visible
    Evidence: .sisyphus/evidence/task-12-element-login.txt

  Scenario: Registration disabled
    Tool: Bash
    Steps:
      - curl -sk https://matrixx.josevictor.me/_matrix/client/v3/register | head
    Expected:
      - Error indicating registration disabled / forbidden
    Evidence: .sisyphus/evidence/task-12-registration-disabled.txt
  ```

  **Commit**: NO

## Final Verification Wave (MANDATORY)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (Element Web flows)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Prefer small commits for `config/kubernetes.nix`, secrets, and each new module.
- Do not push without explicit user approval.

## Success Criteria
- Synapse unaffected + continues serving `matrix.josevictor.me`.
- Dendrite reachable at `matrixx.josevictor.me` and Element Web test login works.

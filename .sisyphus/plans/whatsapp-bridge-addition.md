# WhatsApp Bridge Addition — Work Plan

## TL;DR

> Add **mautrix-whatsapp** bridge to existing Synapse deployment. Create bridge Deployment+Service+PVC in namespace `applications`, configure Synapse to load the bridge's registration YAML, update secrets. GitOps via kubenix + Flux.

**Deliverables**
- New kubenix app module: `modules/kubenix/apps/mautrix-whatsapp.nix`
- Updated `modules/kubenix/apps/matrix-config.enc.nix` with bridge secrets
- Updated `modules/kubenix/apps/matrix.nix` to load bridge registration
- Updated `secrets/k8s-secrets.enc.yaml` with bridge tokens

**Estimated Effort**: Quick
**Parallel Execution**: NO (sequential tasks)
**Critical Path**: secrets → config module → bridge module → synapse update → make manifests → flux reconcile

---

## Context

### Original request
Add WhatsApp bridge to existing Matrix Synapse server following the documented plan (Task 6 from matrix-bridges.md).

### Current state
- **Synapse deployed**: `modules/kubenix/apps/matrix.nix` via Helm chart v3.12.19
- **Namespace**: `applications` (not `matrix` as original plan suggested)
- **Federation**: Disabled
- **Datastores**: External Postgres (`postgresql-18-hl`) + Redis
- **Secrets**: Partially configured (placeholders in `matrix-config.enc.nix`)
- **Bridges**: **NONE deployed yet** (no mautrix files exist)

### Existing patterns (from learnings.md)
- Bridge image: `ghcr.io/mautrix/whatsapp:v0.11.1`
- Bridge port: `29318`
- Bridge DB: `mautrix_whatsapp` (to be auto-created by Postgres)
- Synapse URL: `http://matrix.matrix.svc.cluster.local:8008`
- Bridge PVC: `1Gi` (rook-ceph-block) for session storage
- Replicas: `1` (WhatsApp should run immediately, QR pending)

---

## Work Objectives

### Core Objective
Deploy mautrix-whatsapp bridge that integrates with existing Synapse, enabling WhatsApp-to-Matrix messaging relay-bot mode.

### Must Have
- Bridge Deployment running in namespace `applications`
- Bridge Service (ClusterIP) for internal communication
- PVC for WhatsApp session data
- Registration YAML mounted into both bridge AND Synapse
- Bridge config.yaml with PostgreSQL connection
- AS token and HS token for appservice authentication

### Must NOT Have (Guardrails)
- Do NOT edit `.k8s/` directly (use `make manifests`)
- Do NOT `kubectl apply` as permanent state (GitOps only)
- Do NOT assume bridge will generate registration YAML at runtime (pre-generate it)

---

## Verification Strategy (MANDATORY)

### Test decision
- Infra-style verification only (kubectl logs/describe)
- No automated tests

### Agent-Executed QA Scenarios

**Scenario: WhatsApp bridge deployment is running**
Tool: Bash (kubectl)

Steps:
1. `kubectl -n applications get deployment mautrix-whatsapp -o jsonpath='{.status.readyReplicas}'`
2. Assert: readyReplicas == 1
3. `kubectl -n applications get pods -l app=mautrix-whatsapp -o jsonpath='{.items[0].phase}'`
4. Assert: phase == "Running"
5. `kubectl -n applications logs deployment/mautrix-whatsapp --tail=50 | tee .sisyphus/evidence/whatsapp-bridge-initial.log`
6. Assert: logs contain "Logged in" OR "QR code" OR "not logged in" (acceptable initial states)
7. `kubectl -n applications get pvc -l app=mautrix-whatsapp`
8. Assert: PVC exists and is Bound

Expected Result: Bridge pod running, session PVC bound, logs show initialization state
Evidence: `.sisyphus/evidence/whatsapp-bridge-initial.log`

**Scenario: Synapse recognizes the bridge registration**
Tool: Bash (kubectl + curl)

Steps:
1. `kubectl -n applications get secret mautrix-whatsapp-registration -o jsonpath='{.data.registration\.yaml}' | base64 -d | head -20`
2. Assert: Output contains valid YAML with `as_token`, `hs_token`, `url` fields
3. `kubectl -n applications exec deploy/synapse -- ls -la /app_service_config/`
4. Assert: Directory contains `mautrix-whatsapp-registration.yaml`
5. `kubectl -n applications logs deploy/synapse --tail=100 | grep -i "appservice\|mautrix" | tee .sisyphus/evidence/synapse-bridge-registration.log`
6. Assert: Logs show "Loading appservice" or similar for mautrix-whatsapp

Expected Result: Registration file exists in Synapse, logs show bridge loaded
Evidence: `.sisyphus/evidence/synapse-bridge-registration.log`

**Scenario: Bridge can communicate with Synapse**
Tool: Bash (kubectl logs)

Steps:
1. `kubectl -n applications logs deployment/mautrix-whatsapp --tail=200 | grep -i "matrix\|synapse\|connected" | tee .sisyphus/evidence/whatsapp-bridge-connection.log`
2. Assert: Logs show successful connection to Synapse or connection attempt
3. `kubectl -n applications logs deploy/mautrix-whatsapp --tail=200 | grep -i "error\|failed" | head -20 || echo "No errors in logs"`
4. Assert: No critical errors preventing startup

Expected Result: Bridge successfully communicates with Synapse
Evidence: `.sisyphus/evidence/whatsapp-bridge-connection.log`

---

## Execution Strategy

### Sequential tasks (no parallelization)
All tasks depend on the previous completing successfully.

**Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## TODOs

### 1) Update secrets with WhatsApp bridge tokens

**What to do**
- Add these new secret keys to `secrets/k8s-secrets.enc.yaml`:
  - `mautrix_whatsapp_as_token` - random 64-char string for appservice token
  - `mautrix_whatsapp_hs_token` - random 64-char string for homeserver token
- Note: Reuse existing `postgresql_admin_password` for DB connection

**Recommended Agent Profile**
- Category: unspecified-low
- Skills: writing-nix-code

**References**
- `secrets/k8s-secrets.enc.yaml` - SOPS secrets file
- `modules/kubenix/apps/matrix-config.enc.nix` - existing secret pattern

**Acceptance criteria (agent-exec)**
- `make secrets` opens editor for new keys
- Keys added and file encrypted successfully

---

### 2) Update matrix-config.enc.nix with bridge secrets module

**What to do**
- Edit `modules/kubenix/apps/matrix-config.enc.nix`:
  - Add new Secret resource: `mautrix-whatsapp-env` containing:
    - `MAUTRIX_BRIDGE_AS_TOKEN` (from `mautrix_whatsapp_as_token`)
    - `MAUTRIX_BRIDGE_HS_TOKEN` (from `mautrix_whatsapp_hs_token`)
    - `MAUTRIX_WHATSAPP_POSTGRES_URI` (postgres connection string using `postgresql_admin_password`)
  - Add new Secret resource: `mautrix-whatsapp-registration` containing:
    - `registration.yaml` - the appservice registration file (pre-generated, includes as_token, hs_token, URL, namespaces)
- Use `kubenix.lib.secretsFor` for SOPS integration
- Use `kubenix.lib.secretsInlineFor` for static values

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- `modules/kubenix/apps/matrix-config.enc.nix` - existing secrets pattern
- `modules/kubenix/_lib/default.nix` - `secretsFor`, `secretsInlineFor`, `toYamlStr` helpers
- `modules/kubenix/apps/linkwarden-secrets.enc.nix` - example URI composition
- mautrix-whatsapp docs: https://docs.mau.fi/bridges/go/whatsapp/

**Acceptance criteria (agent-exec)**
- `make manifests` succeeds with new secret definitions
- Generated YAML in `.k8s/applications/` includes both secrets

---

### 3) Create mautrix-whatsapp bridge module

**What to do**
- Create new file: `modules/kubenix/apps/mautrix-whatsapp.nix`
- Define kubernetes resources:
  - PVC: `1Gi` using `rook-ceph-block` storage class
  - Service: ClusterIP, port 29318, name `http`
  - Deployment:
    - Image: `ghcr.io/mautrix/whatsapp:v0.11.1`
    - Replicas: `1`
    - Port: `29318`
    - Environment variables from `mautrix-whatsapp-env` secret
    - Volume mounts:
      - PVC at `/data`
      - `registration.yaml` from secret (read-only) at `/data/registration.yaml`
    - Command: `/usr/bin/mautrix-whatsapp`
    - Args: `--config=/data/config.yaml`, `--registration=/data/registration.yaml`
- ConfigMap: `config.yaml` with bridge configuration:
  - `homeserver.address`: `http://matrix.matrix.svc.cluster.local:8008`
  - `homeserver.domain`: `josevictor.me`
  - `database`: postgres connection
  - `bridge`: relaybot mode settings (per learnings.md)

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- `modules/kubenix/apps/matrix.nix` - Synapse deployment pattern (Helm chart, not raw k8s resources)
- `.sisyphus/notepads/matrix-bridges/learnings.md` - Bridge deployment patterns
- mautrix-whatsapp docs: https://docs.mau.fi/bridges/go/whatsapp/

**Acceptance criteria (agent-exec)**
- `make check` passes with new module
- `make manifests` generates YAML in `.k8s/applications/mautrix-whatsapp.yaml`

---

### 4) Update Synapse to load bridge registration

**What to do**
- Edit `modules/kubenix/apps/matrix.nix`:
  - In Synapse Helm values, uncomment/fix `app_service_config_files`:
    - Map the registration YAML from `mautrix-whatsapp-registration` secret
    - Mount secret volume at `/app_service_config/`
    - Set `app_service_config_files: ["/app_service_config/mautrix-whatsapp-registration.yaml"]`
  - Ensure Synapse pod has permission to read the mounted registration file

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- `modules/kubenix/apps/matrix.nix` - current Synapse Helm config (app_service_config_files commented out on line ~81)
- `modules/kubenix/apps/matrix-config.enc.nix` - where mautrix-whatsapp-registration secret is defined
- Synapse docs: https://element-hq.github.io/synapse/latest/usage/configuration/application_services.html

**Acceptance criteria (agent-exec)**
- `make manifests` succeeds
- Generated Synapse deployment has volume mount for appservice config
- Generated Synapse deployment has `app_service_config_files` configured

---

### 5) Apply via GitOps and verify

**What to do**
- Run the full pipeline:
  - `make manifests`
  - `make check`
  - `git add` + `git commit` (ask user for approval first)
  - `make reconcile` (or `flux reconcile kustomization homelab`)
- Verify deployment:
  - Bridge pod is running
  - PVC is bound
  - Bridge logs show startup/QR prompt
  - Synapse logs show bridge loaded

**Recommended Agent Profile**
- Category: quick
- Skills: git-master, writing-nix-code

**References**
- `Makefile` - manifest generation, checking, reconciliation commands
- `.sisyphus/notepads/matrix-bridges/learnings.md` - verification patterns

**Acceptance criteria (agent-exec)**
- All QA scenarios pass (see Verification Strategy above)
- Bridge deployment: `kubectl -n applications get deploy mautrix-whatsapp` shows Ready
- Bridge logs: `kubectl -n applications logs deploy/mautrix-whatsapp` shows "not logged in" or QR prompt
- Synapse logs show no errors related to appservice loading

---

## Commit Strategy

Suggested commits (ask user before each):
1. Commit 1: Secrets update (SOPS encrypted)
2. Commit 2: Config module update (bridge secrets)
3. Commit 3: Bridge module + Synapse update

---

## Success Criteria

### Verification Commands
```bash
# Bridge is running
kubectl -n applications get pods -l app=mautrix-whatsapp

# PVC is bound
kubectl -n applications get pvc -l app=mautrix-whatsapp

# Bridge initialized (may show QR or "not logged in")
kubectl -n applications logs deployment/mautrix-whatsapp --tail=50

# Synapse loaded the bridge
kubectl -n applications logs deploy/synapse --tail=100 | grep -i "appservice\|mautrix"
```

### Final Checklist
- [ ] mautrix-whatsapp Deployment running (replicas: 1, Ready)
- [ ] PVC bound (1Gi, rook-ceph-block)
- [ ] Bridge logs show startup (QR prompt or "not logged in" acceptable)
- [ ] Synapse logs show appservice loaded
- [ ] Registration YAML mounted in both bridge and Synapse
- [ ] No errors in bridge or Synapse logs

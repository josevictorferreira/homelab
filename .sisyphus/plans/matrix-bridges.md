# Matrix (Synapse) + Bridges (Slack/Discord/WhatsApp) — Work Plan

## TL;DR

> Deploy **Synapse** homeserver (private/LAN-only, federation OFF) at `https://matrix.josevictor.me` behind existing **Cilium Ingress** (LB IP `10.10.10.110`) using `wildcard-tls`. Add **mautrix** bridges (Slack App login outbound-only, Discord LAN-only, WhatsApp QR-pending). GitOps via kubenix + Flux.

**Deliverables**
- New namespace `matrix`
- Synapse Deployment + Service (ClusterIP) + Ingress
- Synapse media PVC `20Gi` (rook-ceph-block)
- mautrix-slack, mautrix-discord, mautrix-whatsapp deployments (manifests present) + PVC for WhatsApp session
- Secrets wiring via `secrets/k8s-secrets.enc.yaml` (SOPS/vals)
- Internal DNS via Blocky: `matrix.josevictor.me → 10.10.10.110`

**Estimated Effort**: Medium
**Parallel Execution**: YES (2 waves)
**Critical Path**: config/kubernetes.nix → secrets → kubenix apps → make manifests → flux reconcile

---

## Context

### Original request
- Choose Matrix server (self-host vs hosted)
- Bridges: Slack → Matrix, Discord → Matrix, WhatsApp → Matrix

### Confirmed decisions
- Homeserver: **Synapse** (self-host)
- Access: **LAN-only**, behind Cilium Ingress; TLS via `wildcard-tls`
- Domain/server_name/user IDs: `matrix.josevictor.me` (`@user:matrix.josevictor.me`)
- Federation: **OFF**
- Bridges: **mautrix** family
  - Slack: `mautrix-slack` **App login** (outbound-only; not Slack Socket Mode)
  - Discord: `mautrix-discord` LAN-only; accept any avatar/proxy limitations
  - WhatsApp: `mautrix-whatsapp`; DoD = deployed + waiting for QR scan
- Bridge mode: **relay-bot only**
- Bridged rooms: **unencrypted** (no E2EE)
- Datastores: reuse shared `postgresql-18` + `redis`
- Postgres DBs to auto-create: `synapse`, `mautrix_slack`, `mautrix_discord`, `mautrix_whatsapp`
- Internal DNS managed via Blocky; reserve `loadBalancer.services.matrix = 10.10.10.138` (reservation/key)
  - Blocky record target remains **10.10.10.110** (shared ingress IP). The `loadBalancer.services` **key** drives the record; the value is only an IP reservation for potential LoadBalancer service annotations.
- Definition of done: bridges **infra-ready only** (pods running + basic health/logs); no message-flow proof required

### Repo facts / conventions to follow
- Kubenix module discovery auto-includes `modules/kubenix/**/*.nix` excluding `_*.nix` (see `modules/kubenix/default.nix`)
- Secrets: `secrets/k8s-secrets.enc.yaml` referenced via `kubenix.lib.secretsFor/secretsInlineFor` (`modules/kubenix/_lib/default.nix`)
- Namespaces are created from `homelab.kubernetes.namespaces` (see `modules/kubenix/bootstrap/namespaces.nix`)
- Pipeline: **NEVER edit `.k8s/*.yaml`**. Use `make manifests` (g→v→u→e).
- Flake eval uses git state: new files must be staged before `make check`.

### External references (authoritative)
- Synapse config docs: https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html
- Synapse appservices: https://element-hq.github.io/synapse/latest/usage/configuration/application_services.html
- mautrix bridges:
  - Slack: https://docs.mau.fi/bridges/go/slack/
  - Discord: https://docs.mau.fi/bridges/go/discord/
  - WhatsApp: https://docs.mau.fi/bridges/go/whatsapp/

---

## Work objectives

### Core objective
Synapse + three bridges deployed via GitOps, reachable on LAN at `https://matrix.josevictor.me`, federation disabled, internal DNS handled, secrets stored in SOPS.

### Must NOT do (guardrails)
- Do not edit `.k8s/` directly (generated)
- Do not `kubectl apply` as “permanent state” (GitOps only)
- Do not remove/patch any Ceph finalizers / delete rook-ceph resources
- Do not expose federation (no 8448 / no federation listeners)

---

## Verification strategy (MANDATORY)

**Universal rule**: agent-executable only (no “user manually verify”).

### Test decision
- Infra-style verification only (kubectl/curl/dig). No unit tests.

### Agent-executed QA scenarios (global)
1) **DNS**: verify Blocky answers `matrix.josevictor.me → 10.10.10.110`
2) **Ingress+TLS+Synapse**: `/_matrix/client/versions` returns 200 JSON over HTTPS
3) **Federation disabled**: `/_matrix/federation/v1/version` not served (404/403)
4) **Bridges**: whatsapp running + QR prompt; slack/discord deployments present (can be scaled 0 until creds)
5) **DB bootstrap**: Postgres job created DBs (or DBs exist)

Evidence capture paths (examples):
- `.sisyphus/evidence/matrix-dns.txt`
- `.sisyphus/evidence/matrix-client-versions.json`
- `.sisyphus/evidence/matrix-pods.txt`

---

## Execution strategy

### Wave 1 (config + secrets)
Task 1,2,3 can run sequentially but fast.

### Wave 2 (apps)
After Wave 1: add kubenix app modules for Synapse + bridges.

Critical Path: Task 1 → Task 2 → Task 4 → Task 6

---

## TODOs

> Each task includes: what to do, references, acceptance criteria + QA.

### 1) Reserve namespace + DNS key + DB list in `config/kubernetes.nix`

**What to do**
- Add namespace mapping: `matrix = "matrix"` under `homelab.kubernetes.namespaces`
- Add reservation key: `homelab.kubernetes.loadBalancer.services.matrix = "10.10.10.138"`
  - Note: Blocky uses the *key* `matrix` to create `matrix.josevictor.me → 10.10.10.110` record (see `blocky-config.enc.nix`). Value `10.10.10.138` is only a reservation for potential future LB Services.
- Add DBs to `homelab.kubernetes.databases.postgres`: `synapse`, `mautrix_slack`, `mautrix_discord`, `mautrix_whatsapp`

**Recommended Agent Profile**
- Category: quick
- Skills: writing-nix-code

**References**
- `config/kubernetes.nix` — loadBalancer pool + namespaces + databases list
- `modules/kubenix/apps/blocky-config.enc.nix` — internal DNS generated from `loadBalancer.services` keys
- `modules/kubenix/apps/postgresql-18.nix` — DB auto-create job driven by `homelab.kubernetes.databases.postgres`

**Acceptance criteria (agent-exec)**
- `make manifests` later succeeds (no eval errors)

---

### 2) Add required secrets to `secrets/k8s-secrets.enc.yaml`

**What to do**
- Add secrets (new keys) for this stack (naming can be adjusted, but keep consistent across Nix modules):
  - Synapse:
    - `synapse_macaroon_secret_key`
    - `synapse_form_secret`
    - `synapse_signing_key` (entire signing key file content)
    - `synapse_admin_username`, `synapse_admin_password`
  - Appservice tokens (random):
    - `mautrix_slack_as_token`, `mautrix_slack_hs_token`
    - `mautrix_discord_as_token`, `mautrix_discord_hs_token`
    - `mautrix_whatsapp_as_token`, `mautrix_whatsapp_hs_token`
  - Slack (provided by you):
    - `slack_app_token` (xapp-...)
    - `slack_bot_token` (xoxb-...)
  - Discord (provided by you):
    - `discord_bot_token`
  - Reuse existing shared creds:
    - Postgres: `postgresql_admin_password` (already present)
    - Redis: `redis_password` (already present)

**DB user note (repo-aligned default)**
- Existing apps typically connect as Postgres superuser `postgres` using `postgresql_admin_password` (e.g. `modules/kubenix/apps/linkwarden-secrets.enc.nix`).
- Plan default: Synapse + bridges do the same (separate DBs, shared `postgres` user).
- If you want per-app DB users: add role/user creation in the Postgres bootstrap job (not currently a repo pattern).

**Token availability note (bridges)**
- Since Slack/Discord tokens are external inputs, default to **deploy Slack+Discord bridges with `replicas: 0`** until tokens are populated in SOPS, then scale to 1.
- WhatsApp can run immediately (QR waiting).

**Recommended Agent Profile**
- Category: unspecified-low
- Skills: writing-nix-code

**References**
- `secrets/k8s-secrets.enc.yaml` — source of truth
- `modules/kubenix/_lib/default.nix` — `secretsFor` / `secretsInlineFor`
- Example secret patterns:
  - `modules/kubenix/apps/n8n-enc.enc.nix`
  - `modules/kubenix/apps/linkwarden-secrets.enc.nix` (URI composition)

**Acceptance criteria (agent-exec)**
- `make manifests` produces encrypted outputs (no plain secrets)

---

### 3) Ensure wildcard cert exists in `matrix` namespace

**What to do**
- Confirm cert-manager module issues/replicates wildcard cert (`wildcard-tls`) into all namespaces listed in `homelab.kubernetes.namespaces`.
- With new `matrix` namespace present, ensure `wildcard-tls` is created there.

**Recommended Agent Profile**
- Category: quick
- Skills: writing-nix-code

**References**
- `modules/kubenix/system/cert-manager.nix` — wildcard cert behavior across namespaces
- `modules/kubenix/bootstrap/namespaces.nix` — namespace creation from config

**Acceptance criteria (agent-exec)**
- After Flux apply: `kubectl -n matrix get secret wildcard-tls` exists

---

### 4) Add kubenix app module: Synapse (`modules/kubenix/apps/matrix.nix`)

**What to do**
- Create Synapse resources in namespace `matrix`:
  - PVC `20Gi` (rook-ceph-block) for `/data` (media store + state)
  - Deployment (1 replica) + Service (ClusterIP, port name `http`)
  - Ingress for host `matrix.josevictor.me` using `kubenix.lib.ingressFor "matrix"` and `wildcard-tls`
- Configure Synapse for:
  - Postgres DB `synapse`
  - Redis optional (only if you want it; keep minimal)
  - Federation disabled: no federation listener/resources; don’t expose 8448
  - Invite-only registration; bootstrap admin via `register_new_matrix_user`
  - `app_service_config_files` pointing at mounted registration yaml(s) for bridges
  - `public_baseurl: https://matrix.josevictor.me/`

**Implementation note (appservice registrations)**
- Do NOT rely on bridges to generate registration YAML at runtime.
- Generate registration YAML once (per mautrix docs) using the bridge container’s `-g`/generate flow, then store the resulting YAML (with tokens pulled from SOPS) as Secret data mounted into Synapse + each bridge.

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- `modules/kubenix/_lib/default.nix` — `ingressFor`, `domainFor`, secrets helpers
- Ingress patterns: `modules/kubenix/apps/n8n.nix` or `modules/kubenix/apps/immich.nix`
- Synapse docs: config + appservices URLs above

**Acceptance criteria (agent-exec)**
- `kubectl -n matrix get deploy,svc,ingress` shows Synapse objects present
- `curl -k -sS https://matrix.josevictor.me/_matrix/client/versions | tee .sisyphus/evidence/matrix-client-versions.json` returns JSON
- Federation check: `curl -k -sS -o /dev/null -w "%{http_code}\n" https://matrix.josevictor.me/_matrix/federation/v1/version` != 200

---

### 5) Add kubenix secrets module for Synapse + bridges (`modules/kubenix/apps/matrix-config.enc.nix`)

**What to do**
- Create Secrets in namespace `matrix`:
  - Synapse config secret(s): `homeserver.yaml` (rendered string), signing key, postgres URI, etc.
  - For each bridge: `config.yaml` + `registration.yaml` as Secret keys
- Use `kubenix.lib.secretsFor/secretsInlineFor` so vals injects values from SOPS.

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- Secret patterns: `modules/kubenix/apps/n8n-enc.enc.nix`, `modules/kubenix/apps/linkwarden-secrets.enc.nix`
- `modules/kubenix/_lib/default.nix` — `toYamlStr`, secrets helpers

**Acceptance criteria (agent-exec)**
- After Flux apply: `kubectl -n matrix get secret | grep -E 'synapse|mautrix'`

---

### 6) Add kubenix modules for bridges (Slack/Discord/WhatsApp)

**What to do**
- Deploy 3 bridge workloads in namespace `matrix` (1 replica each; Deployment or StatefulSet):
  - `mautrix-slack` configured for **App login** (outbound-only)
  - `mautrix-discord` configured for bot token; LAN-only
  - `mautrix-whatsapp` with PVC for session; start in “waiting for QR” state
- Mount each bridge Secret (`config.yaml`, `registration.yaml`) read-only; run bridge with `--no-update`.
- Default scaling:
  - Slack + Discord: `replicas: 0` until tokens are filled
  - WhatsApp: `replicas: 1`

**Implementation note (Synapse URL)**
- Bridges should target Synapse internal URL: `http://matrix.matrix.svc.cluster.local:8008`.

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: writing-nix-code

**References**
- mautrix docs per-bridge URLs above
- Synapse appservices config: app_service_config_files

**Acceptance criteria (agent-exec)**
- `kubectl -n matrix get deploy,sts,pods | tee .sisyphus/evidence/matrix-workloads.txt` shows:
  - synapse running
  - mautrix-whatsapp running
  - mautrix-slack + mautrix-discord present with `replicas: 0` (no crashloop)
- `kubectl -n matrix logs deploy/mautrix-whatsapp | tee .sisyphus/evidence/mautrix-whatsapp.log` contains QR/pairing prompt

---

### 7) Internal DNS via Blocky: ensure record exists

**What to do**
- With `loadBalancer.services.matrix` added, Blocky config should generate `matrix.josevictor.me` record to ingress IP.

**References**
- `modules/kubenix/apps/blocky-config.enc.nix`

**Acceptance criteria (agent-exec)**
- `dig @10.10.10.100 matrix.josevictor.me +short | tee .sisyphus/evidence/matrix-dns.txt` returns `10.10.10.110`

---

### 8) Apply via GitOps and verify end-to-end

**What to do**
- Run:
  - `make manifests`
  - `make check`
  - `make reconcile` (or `flux reconcile kustomization ...` per your workflow)
- Verify:
  - `kubectl -n matrix get all`
  - HTTPS endpoint + federation check + bridge logs

**Acceptance criteria (agent-exec)**
- All QA scenarios in “Verification strategy” pass

---

### 9) Bootstrap admin user (invite-only)

**What to do**
- Exec into Synapse pod and run `register_new_matrix_user` to create 1 admin.

**Acceptance criteria (agent-exec)**
- Admin user exists (command exit 0)

---

## Commit strategy (suggested)
- Commit 1: config/kubernetes.nix (namespace + services key + DB list)
- Commit 2: secrets updates (SOPS encrypted)
- Commit 3: matrix app modules (synapse + bridges + enc secrets module)

---

## Success criteria
- `https://matrix.josevictor.me/_matrix/client/versions` returns 200 from LAN
- Federation endpoint not served
- Synapse running in namespace `matrix`
- mautrix-whatsapp running (QR waiting is OK)
- mautrix-slack + mautrix-discord deployed (may be scaled to 0 until creds)
- Blocky resolves `matrix.josevictor.me → 10.10.10.110`

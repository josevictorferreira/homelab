# Matrix ↔ Slack bridge (mautrix-slack) — homelab kubenix

## TL;DR
Deploy **mautrix-slack** (matrix-org bridge archived) using same pattern as `mautrix-discord`/`mautrix-whatsapp`: raw K8s Deployment+PVC+Service + Synapse appservice registration secret mounted via `matrix.nix`. Slack auth is **manual** (`login token <xoxc> <xoxd d-cookie>`) and **NOT stored** in SOPS. Bridge usage restricted to **@jose:josevictor.me**. **No E2EE rooms**. **Infra-only verification**.

- Deliverables
  - New app module: `modules/kubenix/apps/mautrix-slack.nix`
  - New secrets in `modules/kubenix/apps/matrix-config.enc.nix`: `mautrix-slack-config` + `mautrix-slack-registration`
  - Synapse mounts updated in `modules/kubenix/apps/matrix.nix`
  - New SOPS keys in `secrets/k8s-secrets.enc.yaml`: `mautrix_slack_as_token`, `mautrix_slack_hs_token`
  - Runbook section (in plan) for manual Slack login

Estimated effort: Short
Parallel: YES (some edits parallel)
Critical path: secrets → synapse registration mount → bridge deploy → `make manifests` → flux sync/verify

---

## Context

### Original request
Add last Matrix bridge: Slack. Existing bridges (Discord/WhatsApp) already working.

### Confirmed requirements
- Slack UX target: like weechat-slack; bridge *everything* (channels, DMs, threads, reactions, files).
- Post as self (Slack-side puppeting): YES.
- Workspace count: 1 (company).
- Cannot install Slack App / OAuth approval: NO.
- Slack credential storage: **manual login**, do not store token/cookie in SOPS.
- Bridge access: only `@jose:josevictor.me`.
- Backfill: “from now on”.
- Encrypted Matrix rooms: **disallow**.
- Verification: infra-only (agent verifies infra; user does manual login after deploy).

### Research notes / constraints
- `matrix-org/matrix-appservice-slack` is archived (2026-01-22) → not viable.
- `mautrix/slack` supported token+cookie login per docs: `login token <xoxc> <xoxd>`.
- Slack platform risk (Mar 2026): non‑Marketplace app rate limits may impact history/thread fetch; avoid backfill.

---

## Scope

### IN
- Deploy mautrix-slack in k8s via kubenix.
- Register appservice with Synapse via mounted registration yaml.
- Postgres DB used: `mautrix_slack` (already provisioned by repo).
- Lock permissions to single MXID.
- Disable encryption support.

### OUT
- Storing Slack session token/cookie in SOPS.
- Guaranteeing end-to-end Slack message flow via agent-run verification.
- Slack App / OAuth / Marketplace publication.

---

## Verification strategy

### Automated tests
- None (infra config). Primary verification is agent-executed QA via `make manifests` + k8s checks.

### Agent-executed QA (infra-only)
Agent must verify:
1) manifests build,
2) Synapse loads new appservice registration file,
3) mautrix-slack pod ready and service reachable,
4) bot user exists/responds (at least via logs / management room availability).

---

## Execution strategy (waves)

Wave 1 (parallel edits):
- Task 1: add SOPS keys (as/hs tokens)
- Task 2: add matrix-config secrets (config+registration)
- Task 3: add mautrix-slack app module

Wave 2 (after wave 1):
- Task 4: mount registration into Synapse (`matrix.nix`)
- Task 5: generate manifests + flux reconcile + infra verification

Wave 3 (optional, non-verifiable):
- Task 6: runbook + user manual login + expectations

---

## TODOs

### 1) Add SOPS keys for mautrix-slack appservice tokens

**What to do**:
- Add new encrypted keys to `secrets/k8s-secrets.enc.yaml`:
  - `mautrix_slack_as_token`
  - `mautrix_slack_hs_token`
- Values: generate strong random strings (>=32 bytes). Use repo workflow: `make secrets`.

**Must NOT do**:
- Don’t add Slack xoxc/xoxd tokens.
- Don’t commit plaintext.

**Recommended Agent Profile**:
- Category: `unspecified-high` (Nix + secrets + GitOps)
- Skills: `writing-nix-code`

**Parallelization**: YES (Wave 1)

**References**:
- `secrets/k8s-secrets.enc.yaml` (existing mautrix_* keys for discord/whatsapp)
- Repo rule: `.docs/rules.md` (SOPS/vals pipeline; no placeholders)

**Acceptance criteria (agent-executable)**:
- `sops -d secrets/k8s-secrets.enc.yaml | grep -E '^mautrix_slack_(as_token|hs_token):'` returns 2 lines.

**QA scenario**:
- Tool: Bash
- Steps: decrypt + grep keys; ensure no `xoxc`/`xoxd` strings present.

---

### 2) Add mautrix-slack config+registration secrets (kubenix)

**What to do**:
- In `modules/kubenix/apps/matrix-config.enc.nix`, add:
  - `kubernetes.resources.secrets."mautrix-slack-registration"` (stringData `registration.yaml`)
  - `kubernetes.resources.secrets."mautrix-slack-config"` (stringData `config.yaml`)
- Registration YAML should mirror existing pattern:
  - `id = "slack"`
  - `url = http://mautrix-slack.${namespace}.svc.cluster.local:29333`
  - `sender_localpart = "slackbot"`
  - `as_token/hs_token` from `kubenix.lib.secretsInlineFor "mautrix_slack_*"`
  - namespaces users regexes for bot + puppets: `@slackbot:josevictor\.me`, `@slack_.*:josevictor\.me`
- Config YAML must:
  - point homeserver to Synapse service URL used by other bridges
  - use Postgres URI to DB `mautrix_slack` on `postgresql-18-hl.${namespace}.svc.cluster.local:5432` w/ admin pw secret
  - set `bridge.permissions` so only `@jose:josevictor.me` has `admin`
    - preferred: omit any `"*"` wildcard entry (only explicit MXID)
    - if bridge requires a wildcard entry, use `"*" = "relay"` BUT keep relay mode disabled
  - set `bridge.kick_matrix_users = true` (so other Matrix users don’t linger in portals when not allowed)
  - disable encryption (`bridge.encryption.allow=false`)
  - avoid history backfill (`backfill.max_initial_messages=0` or `backfill.enabled=false`)
  - still “bridge everything”: set Slack connector conversation listing to include all conversations (likely `slack.backfill.conversation_count=-1`) while keeping message backfill 0.
  - IMPORTANT: mautrix bridges have 2 config schema variants (see repo precedent):
    - WhatsApp uses top-level `database.*`
    - Discord uses nested `appservice.database.*`
    - For Slack: verify against upstream example-config and match the correct structure.

**Must NOT do**:
- Don’t enable relay mode.
- Don’t add any ingress.

**Recommended Agent Profile**:
- Category: `unspecified-high`
- Skills: `writing-nix-code`

**Parallelization**: YES (Wave 1)

**References**:
- `modules/kubenix/apps/matrix-config.enc.nix` (existing `mautrix-discord-*` + `mautrix-whatsapp-*` secrets)
- Upstream auth doc: https://docs.mau.fi/bridges/go/slack/authentication.html
- Upstream config knobs (Slack): `mautrix/slack` `pkg/connector/example-config.yaml`
- Upstream common config knobs: `mautrix/go` `bridgev2/matrix/mxmain/example-config.yaml`

**Acceptance criteria (agent-executable)**:
- `make manifests` succeeds after staging changes.
- Generated secret manifest includes names `mautrix-slack-config` and `mautrix-slack-registration` in `.k8s/` output.

**QA scenarios**:
- Tool: Bash
- Steps: `git add` new/changed nix files → `make manifests` → search generated YAML for secret names.

---

### 3) Add `mautrix-slack` app module (Deployment/Service/PVC)

**What to do**:
- Create `modules/kubenix/apps/mautrix-slack.nix` by copying pattern from `mautrix-discord.nix`:
  - PVC 1Gi `rook-ceph-block` RWO
  - Service ClusterIP port **29333** (verify upstream default; repo has no 29333 usage today)
  - Deployment:
    - initContainer copies `/config-src/config.yaml` + `/registration-src/registration.yaml` into `/data`
    - main container runs `dock.mau.dev/mautrix/slack:<PINNED_VERSION>`
    - `imagePullSecrets = [{ name = "mau-registry-secret"; }]`
    - volumes: PVC + secret `mautrix-slack-config` + secret `mautrix-slack-registration`

**Must NOT do**:
- Don’t use `:latest` if avoidable; pin release tag or digest.

**Default to use** (unless you have a reason not to):
- Pin to the latest upstream release tag at time of change (not `latest`).

**Note**:
- `modules/kubenix/default.nix` auto-discovers new `modules/kubenix/apps/*.nix` files (unless prefixed `_`). No extra imports needed.

**Recommended Agent Profile**:
- Category: `unspecified-high`
- Skills: `writing-nix-code`

**Parallelization**: YES (Wave 1)

**References**:
- `modules/kubenix/apps/mautrix-discord.nix` (initContainer + mounts + secrets)
- `modules/kubenix/apps/mau-registry-secret.enc.nix` (registry auth secret used by other mautrix images)

**Acceptance criteria (agent-executable)**:
- `make manifests` renders a Deployment/Service/PVC for `mautrix-slack` into `.k8s/apps/`.

---

### 4) Register Slack appservice in Synapse (mount + app_service_config_files)

**What to do**:
- Update `modules/kubenix/apps/matrix.nix`:
  - Add slack registration file path to `extraConfig.app_service_config_files`:
    - `/synapse/config/conf.d/mautrix-slack-registration.yaml`
  - Add secret volume + volumeMount for `mautrix-slack-registration` similar to WhatsApp/Discord.

**Must NOT do**:
- Don’t change server_name / publicBaseurl.

**Recommended Agent Profile**:
- Category: `unspecified-high`
- Skills: `writing-nix-code`

**Parallelization**: NO (Wave 2; depends on Tasks 2/3)

**References**:
- `modules/kubenix/apps/matrix.nix` (existing mount for `mautrix-whatsapp-registration` + optional discord)

**Acceptance criteria (agent-executable)**:
- After deploy, Synapse pod has mounted file:
  - `kubectl exec -n apps deploy/synapse-matrix-synapse -- ls /synapse/config/conf.d/mautrix-slack-registration.yaml`
- Synapse logs show appservice loaded (grep “appservice” + “slack” if present).

---

### 5) Generate manifests + Flux deploy + infra verification

**What to do**:
- Ensure git staging for new files before evaluation (flake uses git state).
- Run:
  - `make manifests`
  - Commit + push (to trigger Flux)
  - `make reconcile` (or wait for Flux interval)
- Verify k8s:
  - mautrix-slack pod ready
  - Synapse pod ready
  - Service reachable inside cluster (curl)

**Recommended Agent Profile**:
- Category: `unspecified-high`
- Skills: `kubernetes-tools` (if available), else plain bash

**Parallelization**: NO (Wave 2)

**References**:
- `.docs/rules.md` (flake uses git state; must stage before `make manifests`)
- `Makefile` targets: `make manifests`, `make reconcile`

**Acceptance criteria (agent-executable)**:
- `make manifests` exits 0.
- Flux applies new resources (e.g., `kubectl get deploy -n apps | grep mautrix-slack`).
- `kubectl wait -n apps --for=condition=available deploy/mautrix-slack --timeout=180s` succeeds.
- In-cluster connectivity:
  - `kubectl run -n apps --rm -i --restart=Never curl --image=curlimages/curl -- sh -lc 'curl -sf http://mautrix-slack.apps.svc.cluster.local:29333/metrics || curl -sf http://mautrix-slack.apps.svc.cluster.local:29333/'` succeeds.

**Optional (best-effort) checks**:
- Synapse profile endpoint reachable (no jq dependency):
  - `kubectl run -n apps --rm -i --restart=Never curl --image=curlimages/curl -- sh -lc 'curl -sf http://synapse-matrix-synapse.apps.svc.cluster.local:8008/_matrix/client/v3/profile/%40slackbot%3Ajosevictor.me | grep -qi displayname'`

**QA scenarios**:
- Scenario: Bridge pod healthy w/out Slack login
  - Tool: Bash
  - Steps: wait for deploy available; tail logs; ensure no crashloop.
- Scenario: Synapse sees registration file
  - Tool: Bash
  - Steps: exec into synapse container and `ls` conf.d file.

---

### 6) Manual login runbook (documented; not agent-verifiable)

**Goal**: you login to Slack from Matrix after infra ready.

**Steps (per docs)**:
1) In Slack web, extract:
   - token: `xoxc-...` via devtools localStorage:
     - `JSON.parse(localStorage.localConfig_v2).teams.<TEAM_ID>.token`
   - cookie: browser cookie named `d` (`xoxd-...`)
2) In Matrix, DM bridge bot: `@slackbot:josevictor.me`
3) Send: `login token <xoxc-token> <xoxd-cookie>`
4) Confirm portal rooms appear; message flow works.
5) Send `help` to see bridge commands in your version.

**Guardrails**:
- Token+cookie grants broad Slack access; treat as highly sensitive.
- You will send it to the bot in a Matrix DM; assume that room is **not E2EE** (we’re disallowing encryption). Use a trusted client and consider redacting the message after successful login.
- If Slack token expires or bridge restarts and loses session, redo step (PVC+DB should persist, but assume re-login may be needed).
- Avoid backfill; keep “from now on”.

---

## Rollback / disable plan

Fast rollback options (GitOps-friendly):
- Disable Slack bridge generation by renaming module to `_mautrix-slack.nix` (kubenix ignores `_` files), re-run `make manifests`, commit, flux reconcile.
- Also remove Slack registration from `modules/kubenix/apps/matrix.nix` `app_service_config_files` + volume mounts.
- Verify Synapse restarts cleanly without the slack registration file.

---

## Success criteria (overall)
- mautrix-slack deployed + stable (no crashloop).
- Synapse loads Slack appservice registration file.
- Bridge bot is reachable in Matrix (management room can be created).
- Manual login instructions documented.

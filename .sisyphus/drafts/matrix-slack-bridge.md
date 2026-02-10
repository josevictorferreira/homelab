# Draft: Matrix ↔ Slack bridge (homelab)

## Objective
- Add last Matrix bridge: Slack, deployed via kubenix/Flux like existing mautrix-* bridges.

## Known context (from user)
- Existing bridges working: mautrix-discord + mautrix-whatsapp.
- Target: homelab k8s cluster (kubenix-generated manifests, Flux GitOps).
- Desired Slack UX: like weechat-slack; see messages “as they are”; send as own user.
- Scope: everything (channels + DMs + threads + reactions + files).
- Workspaces: 1 (company workspace).
- Slack app install approval: **NO** (can’t get admin approval).
- Slack secret handling: **manual login** after deploy (don’t store token/cookie in SOPS).
- Bridge access: **only me**.
- Backfill: **from now on** (avoid history backfill).

## Candidate solutions (TBD after research)
- Option A: mautrix-slack (if maintained/usable)
- Option B: matrix-appservice-slack (python)
- Option C: hookshot / other modern bridge (if Slack support)

## Key decisions to confirm
- Bridge implementation choice (mautrix-slack vs alternatives)
- Slack auth model: **puppeting / send as self** (strong preference) vs relay-bot fallback
- Scope: channel bridging only vs DMs + threads + reactions + file uploads
- Multi-workspace support needed?
 - Slack admin constraints: can create/install Slack app? or must use session token/cookie method.

## Constraints / guardrails
- Follow repo conventions: kubenix app module + separate *-config.enc.nix for secrets.
- No plaintext secrets; use SOPS keys in secrets/k8s-secrets.enc.yaml.
- Don’t edit .k8s YAML directly; use `make manifests` pipeline.

## Open questions
- Slack: can you create/install a Slack app in the company workspace (admin approval)?
- If no app install possible: are you OK using session token/cookie (like weechat), with ToS/brittleness risk?
- Backfill expectation: full history vs “from now on” (given Mar 2026 rate limits risk).
- Matrix side: existing homeserver + appservice pattern to reuse? (namespace, registration)
- Operational: desired namespaces/labels, resource limits, persistence needs.

## Research findings
- **matrix-appservice-slack is dead**: matrix-org/matrix-appservice-slack archived 2026-01-22; matrix.org retired public Slack bridge. Not recommended.
- **Recommended bridge: mautrix-slack** (mautrix/slack, Go). Active releases (latest seen: 2025-11). Docs: https://docs.mau.fi/bridges/go/slack/
- **Slack platform risk (Mar 3 2026)**: new strict rate limits for *non-Marketplace* apps (notably conversations.history/replies). Could cause slow backfill/thread sync. Needs expectation-setting.

## Working assumption (based on answers)
- We will likely need **mautrix-slack “login token”** style auth (session token + cookie), since OAuth/app install isn’t possible.
- This implies higher breakage/ToS risk; plan must include guardrails and rollback (disable bridge) steps.

## Verification stance (confirmed)
- Plan will enforce **infra-only verification** (agent verifies pods/registration/bot responsiveness).
- End-to-end Slack message flow cannot be agent-verified without storing token/cookie; user will do manual login after deploy.

## Permissions stance (confirmed)
- Bridge should be usable by **only** `@jose:josevictor.me`.

## Repo-local findings (homelab)
- Existing pattern files:
  - modules/kubenix/apps/mautrix-discord.nix
  - modules/kubenix/apps/mautrix-whatsapp.nix
  - modules/kubenix/apps/matrix-config.enc.nix (bridge config + registration secrets)
  - modules/kubenix/apps/matrix.nix (Synapse mounts registration + app_service_config_files)
- config/kubernetes.nix already references: "mautrix_slack" (likely placeholder/desired app list).

## What we’ll need to add/change (high-level)
- New kubenix app module for bridge (likely: modules/kubenix/apps/mautrix-slack.nix) following discord/whatsapp pattern:
  - PVC + Service + Deployment
  - initContainer copies config+registration from secrets into /data
  - main container runs dock.mau.dev/mautrix/slack image
- New secrets generated in matrix-config.enc.nix:
  - mautrix-slack-registration (appservice registration YAML)
  - mautrix-slack-config (bridge config.yaml)
- Synapse integration in matrix.nix:
  - mount registration YAML into Synapse container
  - append to app_service_config_files
- SOPS secrets keys (at minimum): mautrix_slack_as_token, mautrix_slack_hs_token
  - Slack auth secrets depend on chosen auth mode (app/relay tokens vs user token login).

# Hermes Profiles Shared Configuration Plan

## Goal

Run all Hermes profiles (`ted`, `kira`, `mel`, `spike`, `luna`) from a **single
container** with a **single shared configuration**, where the only per-profile
differences are:

- `model.default` (the main model)
- `skills.disabled` (per-profile disabled skills)
- `kanban.dispatch_in_gateway: true` on **spike** only
- the WhatsApp block on **kira** only (WhatsApp is inherently kira-specific)

Each profile keeps its own `SOUL.md`, `AGENTS.md`, memory, sessions, and state.

## Mechanisms (verified against the running image + docs)

### 1. Shared config via Managed Scope (`HERMES_MANAGED_DIR`)

`hermes_cli/managed_scope.py`: when `HERMES_MANAGED_DIR` points at an existing
directory, its `config.yaml` is overlaid **on top of** each profile's config via
a leaf-level deep-merge — **managed values win per leaf key** and cannot be
overridden per profile. `${VAR}` refs in the managed config expand against the
process env only. Fail-open (a malformed managed file is logged and ignored).

We set `HERMES_MANAGED_DIR=/opt/data` so the **existing** default-profile config
at `/opt/data/config.yaml` *is* the shared overlay. Consequence: any key present
in `/opt/data/config.yaml` is pinned for every profile. Therefore the keys that
must vary per profile are **removed** from it:

- `model.default`
- `skills.disabled`
- `kanban.dispatch_in_gateway`

Everything else (providers, toolsets, terminal, web/browser, display, voice,
platforms baseline, etc.) lives in `/opt/data/config.yaml` and is forced
identical across all profiles — exactly the intent.

### 2. Single container via multiplexing

`docs/user-guide/multi-profile-gateways` → "one gateway for all profiles
(multiplexing)". Enable on the default profile:

```yaml
gateway:
  multiplex_profiles: true
```

Then a single `hermes gateway run` (default profile, `HERMES_HOME=/opt/data`)
enumerates every profile under `/opt/data/profiles/*`, brings up each profile's
enabled platforms under that profile's own credentials, and routes each inbound
message to the owning profile. Per turn it resolves the routed profile's config,
skills, memory, SOUL, **and provider keys** — nothing is shared across profiles
except the managed overlay.

This replaces the 5 per-profile gateway containers with one container.

### 3. Per-profile secrets must live in each profile's `.env`

In multiplex mode each profile resolves its credentials from its own
`profiles/<name>/.env` (chmod 600); env vars cannot be per-profile in a single
process. Today the per-container `MATRIX_ACCESS_TOKEN` env injection does this
job — that no longer works with one container.

The container boot script materializes each profile's token into its `.env`
from distinct container env vars (sourced from the existing `hermes-agent-env`
SOPS secret), idempotently upserting:

- `profiles/ted/.env`   ← `MATRIX_ACCESS_TOKEN`
- `profiles/kira/.env`  ← `HERMES_KIRA_MATRIX_ACCESS_TOKEN` + `WHATSAPP_*`
- `profiles/mel/.env`   ← `HERMES_MEL_MATRIX_ACCESS_TOKEN`
- `profiles/spike/.env` ← `HERMES_SPIKE_MATRIX_ACCESS_TOKEN`
- `profiles/luna/.env`  ← `HERMES_LUNA_MATRIX_ACCESS_TOKEN`

The root/default profile (`/opt/data`) has **no** Matrix token, so as the
multiplexer host it connects no messaging platform of its own.

## Per-profile config.yaml after the refactor

```yaml
# profiles/ted/config.yaml (and mel, luna — analogous)
model:
  default: <profile-model>
skills:
  disabled: [ ... ]

# profiles/kira/config.yaml
model: { default: <model> }
skills: { disabled: [ ... ] }
whatsapp: { ... }            # kira only
platforms: { whatsapp: { enabled: true } }

# profiles/spike/config.yaml
model: { default: <model> }
skills: { disabled: [ ... ] }
kanban:                      # spike only
  dispatch_in_gateway: true
  orchestrator_profile: irenicus
  default_assignee: valygar
  max_in_progress_per_profile: 1
```

## Homelab implementation (`modules/kubenix/apps/hermes-agent.nix`)

1. Replace the 5 `gatewayProfiles` containers with one `gateway` container.
2. `commonEnv` adds `HERMES_HOME=/opt/data` and `HERMES_MANAGED_DIR=/opt/data`.
3. Inject every per-profile Matrix token + kira WhatsApp creds as distinct env
   vars from `hermes-agent-env`.
4. Boot command: run the shared bootstrap **once**, upsert per-profile `.env`
   tokens, then `exec hermes gateway run`.
5. Keep the root `fix-profile-permissions` init container and the separate
   dashboard deployment.
6. `make manifests`, then commit/push **only after explicit approval** so Flux
   reconciles the cutover.

## Cutover ordering (important)

Trimmed profile configs only work once `HERMES_MANAGED_DIR` is active (new
container). So the CephFS config edits and the new manifest must land together:

1. Back up all `config.yaml` / `.env`.
2. Stage `/opt/data/config.yaml` (multiplex flag + remove varying keys) and the
   trimmed per-profile configs.
3. Deploy the single-container manifest (commit/push → Flux). The hard cutover
   (Recreate strategy) brings up the multiplexer with the managed overlay active.

## Validation

1. `make manifests` succeeds.
2. One gateway pod, single container, `Running`.
3. `hermes gateway list` / `hermes status` reports the multiplexer + all profiles.
4. Each profile's Matrix account connects under its own token.
5. `hermes -p <p> config` shows shared keys resolving from managed and
   `model.default` / `skills.disabled` from the profile.
6. spike's kanban dispatch is active; kira's WhatsApp is enabled.

## Non-Goals

- Per-profile process isolation / independent crash domains (multiplex trades
  these for a single supervised process — acceptable here).
- Putting any secret (e.g. the omniroute `api_key`) into git; secrets stay on
  CephFS `.env`/`config.yaml` and SOPS as today.

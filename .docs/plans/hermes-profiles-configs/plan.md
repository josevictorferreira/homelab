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

We set `HERMES_MANAGED_DIR=/opt/data/managed` (a **dedicated** file, not
`/opt/data/config.yaml` itself — that would pin host-only keys like
platforms/whatsapp onto every profile). `/opt/data/managed/config.yaml` holds all
keys that must be identical across profiles. The keys that vary per profile are
**absent** from it (so they aren't pinned):

- `model.default`
- `skills.disabled`
- `kanban.dispatch_in_gateway` (spike), WhatsApp enablement (kira)

Everything else (providers, toolsets, terminal, web/browser, display, voice,
matrix settings, etc.) lives in the managed file and is forced identical across
all profiles — exactly the intent.

### 2. Topology: 5 per-profile gateway containers (one pod)

**FINAL decision** — keep the proven model: the `hermes-agent-gateway`
Deployment runs **5 containers in one pod**, `gateway-<profile>` each, via
`gatewayProfiles` + `gatewayContainer`. Each container runs
`hermes -p <profile> gateway run` with its own `MATRIX_ACCESS_TOKEN` (per-profile
SOPS key) and `HERMES_HOME=/opt/data/profiles/<p>`, so every profile connects its
own Matrix account — true per-account isolation, independent crash domains.

**Single-container alternatives were tried and rolled back:**

- **Multiplex (`gateway.multiplex_profiles`)** can't give each profile its own
  Matrix token in v2026.6.19: `gateway/config.py` `_apply_env_overrides` resolves
  `MATRIX_ACCESS_TOKEN` from the **process-global** `os.environ` (overriding any
  per-profile `platforms.matrix.token`), and `matrix.py` `check_matrix_requirements`
  gates on `os.getenv` too — neither uses the scope-aware `get_secret`. One token
  is forced onto every profile. (Also only the top-level `multiplex_profiles` key
  is honored; the nested form is a no-op.) Fixing it needs a custom image patch or
  upstream PR.
- **One container, 5 processes** (a `run_gw` launcher backgrounding each gateway):
  works, but offers no advantage over 5 containers while losing per-process
  resource limits and independent restart — rolled back.

### 3. Per-profile secrets (unchanged from the proven setup)

Each `gateway-<profile>` container injects its own `MATRIX_ACCESS_TOKEN` from the
matching `hermes-agent-env` SOPS key (`MATRIX_ACCESS_TOKEN`,
`HERMES_KIRA_MATRIX_ACCESS_TOKEN`, …); kira also gets `WHATSAPP_*`. Shared Matrix
settings (`MATRIX_HOMESERVER`, etc.) come from `envFrom`.

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

The only change vs. the original 5-container setup: add
`HERMES_MANAGED_DIR=/opt/data/managed` to `commonEnv`. Everything else
(`gatewayProfiles`, `gatewayContainer` with per-profile `MATRIX_ACCESS_TOKEN` +
`HERMES_HOME`, the `fix-profile-permissions` init container, dashboard) is the
proven config, unchanged.

1. Add `HERMES_MANAGED_DIR=/opt/data/managed` to `commonEnv` (shared by all 5).
2. `make manifests`, then commit/push **only after explicit approval** so Flux
   reconciles.

## CephFS config edits (one-time, already applied)

1. Backups written to `~/Homelab/hermes/.refactor-backup-*`.
2. `prep`: build `/opt/data/managed/config.yaml` (shared keys; per-profile/host
   keys excluded). Group-readable (gid 2002).
3. `trim`: reduce each `profiles/<p>/config.yaml` to deltas (`model.default` +
   `skills.disabled`; + kira whatsapp, + spike kanban).

## Validation (all passed 2026-06-21)

1. `make manifests` succeeds.
2. Gateway pod `5/5 Running`, all container restart counts 0.
3. Each profile's Matrix account connects under its own token — verified distinct
   identities `@ted/@kira/@mel/@spike/@luna:josevictor.me` on the live boot.
4. Per-profile `model.default` differs (e.g. ted `deepseek-v4-flash`, spike
   `kimi-k2.6`) while shared keys (`timezone`, `model.provider`) resolve from
   the managed overlay — confirmed inside `gateway-ted`.
5. spike's kanban dispatch intact; kira's WhatsApp enabled.

## Non-Goals

- Multiplex mode (`gateway.multiplex_profiles`) — rejected; cannot do per-profile
  Matrix tokens in this version (see §2).
- Putting any secret (e.g. the omniroute `api_key`) into git; secrets stay on
  CephFS `.env`/`config.yaml` and SOPS as today.

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

### 2. Single container: per-process, NOT multiplex

**Multiplex (`gateway.multiplex_profiles`) was evaluated and rejected** for this
Hermes version (v2026.6.19). Although it serves all profiles from one process,
it cannot give each profile its own Matrix token: `gateway/config.py`
`_apply_env_overrides` resolves `MATRIX_ACCESS_TOKEN` from the **process-global**
`os.environ` and overrides any per-profile `platforms.matrix.token`; the
multiplexer never overlays a profile's `.env` into `os.environ` at adapter
startup. Result: one token is forced onto every profile, so only one Matrix
account connects. (Also: only the **top-level** `multiplex_profiles` key is
honored — the documented nested `gateway.multiplex_profiles` is a no-op in
`load_gateway_config`.)

Instead, the single container's command launches **one gateway process per
profile**, each self-restarting:

```sh
run_gw() {                       # prof, matrix-token, [EXTRA_ENV=val ...]
  while true; do
    env MATRIX_ACCESS_TOKEN="$tok" HERMES_HOME="/opt/data/profiles/$prof" "$@" \
      hermes -p "$prof" gateway run --no-supervise
    sleep 5                      # restart on crash; one crash ≠ all down
  done
}
run_gw ted "$TED_MATRIX_TOKEN" & ... & run_gw kira "$KIRA_MATRIX_TOKEN" WHATSAPP_*=... &
wait
```

This is the proven per-profile credential isolation, collapsed into one pod —
one container, one shared config, only credentials differ per process.

### 3. Per-profile secrets via per-process env

Each profile gateway process gets its **own** `MATRIX_ACCESS_TOKEN` (and kira its
`WHATSAPP_*`) in its process env, sourced from distinct `hermes-agent-env` SOPS
keys exposed as `TED_MATRIX_TOKEN`, `KIRA_MATRIX_TOKEN`, … The launcher passes
them per `run_gw` invocation, so profiles never share a token. Shared Matrix
settings (`MATRIX_HOMESERVER`, etc.) come from the container `envFrom` and are
identical across processes. The default profile (`/opt/data`) gateway is never
launched, so it connects no platform.

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
2. `commonEnv` sets shared `HOME=/opt/data` and `HERMES_MANAGED_DIR=/opt/data/managed`
   (`HERMES_HOME` is set per-process in the launcher, not in `commonEnv`).
3. Inject every per-profile Matrix token + kira WhatsApp creds as distinct env
   vars from `hermes-agent-env` (`TED_MATRIX_TOKEN`, `KIRA_MATRIX_TOKEN`, …).
4. Boot command: run the shared bootstrap **once**, then `run_gw <profile> <token>`
   for each of the 5 profiles in the background + `wait`.
5. Container resources capped at the apps-namespace LimitRange max
   (**cpu 2 / memory 4Gi** per container) — all 5 processes share that budget.
6. Keep the root `fix-profile-permissions` init container and the separate
   dashboard deployment.
7. `make manifests`, then commit/push **only after explicit approval** so Flux
   reconciles the cutover.

## Cutover ordering (important)

Trimmed profile configs only work once `HERMES_MANAGED_DIR` is active (new
container). So the CephFS config edits and the new manifest must land together:

1. Back up all `config.yaml` / `.env` (script writes `~/Homelab/hermes/.refactor-backup-*`).
2. `prep`: create `/opt/data/managed/config.yaml` (shared keys); the default
   profile config needs no platform edits (its gateway is never launched).
3. Deploy the single-container manifest (commit/push → Flux). Recreate strategy
   brings up the 5 per-process gateways with the managed overlay active.
4. `trim`: reduce each `profiles/<p>/config.yaml` to deltas, then restart to
   confirm the trimmed configs still produce 5 working gateways.

## Validation (all passed 2026-06-21)

1. `make manifests` succeeds.
2. One gateway pod, single container, `Running` (restart count 0, no launcher
   restart messages).
3. `ps` shows 5 `hermes -p <profile> gateway run` processes.
4. Each profile's Matrix account connects under its own token — verified distinct
   identities `@ted/@kira/@mel/@spike/@luna:josevictor.me`.
5. Per-profile `model.default` differs (e.g. ted `deepseek-v4-flash`, spike
   `kimi-k2.6`) while shared keys (`timezone`, `model.provider`) resolve from
   the managed overlay.
6. spike's kanban dispatcher is embedded + dispatching; kira's WhatsApp enabled.

## Non-Goals

- Multiplex mode (`gateway.multiplex_profiles`) — rejected; cannot do per-profile
  Matrix tokens in this version (see §2).
- Putting any secret (e.g. the omniroute `api_key`) into git; secrets stay on
  CephFS `.env`/`config.yaml` and SOPS as today.

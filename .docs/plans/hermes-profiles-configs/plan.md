# Hermes Profiles Shared Configuration Plan

## Goal

Reduce duplicated Hermes profile configuration across `kira`, `ted`, `mel`, `spike`, and `luna` while keeping per-profile identity and state isolated.

## Documentation Finding

Hermes does **not** support profile-to-default-profile inheritance. A named profile's `config.yaml` does not fall back to the default profile config at `/opt/data/config.yaml` when a key is omitted.

The supported mechanism for sharing config across profiles is **Managed Scope**:

- A managed directory contains a shared `config.yaml` and optional `.env`.
- The directory defaults to `/etc/hermes/`, but can be changed with `HERMES_MANAGED_DIR`.
- Managed config applies to all profiles.
- Merge behavior is leaf-level: only the exact keys present in managed config are pinned.
- Managed keys win over profile config and cannot be overridden per profile.

## Proposed Approach

Use Managed Scope for values that are identical across all Hermes profiles.

1. Create a shared managed config file for common settings.
2. Mount it into the Hermes gateway containers, for example at `/opt/data/managed/config.yaml`.
3. Set `HERMES_MANAGED_DIR=/opt/data/managed` in the shared gateway environment.
4. Remove duplicated managed keys from each profile's `config.yaml`.
5. Keep genuinely per-profile values in each profile config.

## What Should Go in Managed Config

Good candidates:

- Shared model defaults.
- Shared tool/runtime settings.
- Shared terminal behavior.
- Shared gateway or browser integration settings.
- Any config key that should be identical for every profile.

Keep per-profile:

- SOUL/personality configuration.
- Profile-specific model overrides.
- Profile-specific working directories.
- Profile-specific tokens or credentials.
- Anything that may need to differ between agents.

## Important Tradeoff

Managed Scope is not an override-able fallback system.

If a key is present in managed config, profile config cannot override it. Therefore, only move keys into managed config when they should be globally fixed for every profile.

## Homelab Implementation Sketch

In `modules/kubenix/apps/hermes-agent.nix`:

1. Add a managed config source, likely via ConfigMap or a CephFS-backed file.
2. Mount the managed directory into every profile gateway container.
3. Add this to `commonEnv`:

   ```yaml
   HERMES_MANAGED_DIR: /opt/data/managed
   ```

4. Regenerate manifests with:

   ```bash
   make manifests
   ```

5. Commit and push only after explicit user approval so Flux can reconcile.

## Validation Plan

1. Inspect current live profile configs under `~/Homelab/hermes/profiles/*/config.yaml`.
2. Identify keys duplicated across all profiles.
3. Move only identical global keys into managed config.
4. Confirm profile configs retain required per-profile differences.
5. Run `make manifests` successfully.
6. After deployment, verify inside a profile gateway container:

   ```bash
   echo "$HERMES_MANAGED_DIR"
   hermes doctor
   hermes config
   ```

7. Confirm managed keys show their managed source and profile-specific keys still resolve from the profile config.

## Non-Goals

- Do not use gateway multiplexing as a config-sharing mechanism; it does not provide config inheritance.
- Do not rely on profile cloning; cloning copies config once and does not keep configs shared.
- Do not put high-sensitivity secrets in managed `.env`, because managed files are intended to be readable by all profiles.

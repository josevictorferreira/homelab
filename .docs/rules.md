# Homelab Rules & Lessons

## NixOS Profile System

### Profile Discovery Auto-Generates Roles
**Lesson:** Roles are automatically discovered from `modules/profiles/*.nix` filenames. Every `.nix` file = a valid role.
**Context:** Adding a new role like "tailscale-router" requires creating a corresponding `.nix` file, even if it's just a marker.
**Verify:** `ls modules/profiles/*.nix | grep <role-name>`

### Secrets Defined in Common Module
**Lesson:** Check `modules/common/sops.nix` before defining secrets in profiles. Common secrets are already declared there.
**Context:** Duplicate secret definitions cause Nix evaluation errors. The common module defines shared secrets like `tailscale_auth_key`.
**Verify:** `grep "secret_name" modules/common/sops.nix`

## Nix Flake Evaluation

### Flake Uses Git State, Not Working Directory
**Lesson:** `make check` and `make manifests` evaluate the flake from git state. New files must be `git add`-ed before validation/manifest generation.
**Context:** Nix flakes are pure and use git to determine the source tree. Unstaged files (especially `modules/kubenix/**/*.nix`) are invisible to `nix flake check` and `make manifests`.
**Verify:** `git status` - ensure new files are staged, then `nix build .#gen-manifests` to confirm discovery

## Tailscale Integration Pattern

### Subnet Router Role Detection
**Lesson:** Use `builtins.elem "tailscale-router" hostConfig.roles` to detect if a node should act as subnet router.
**Context:** This allows conditional configuration (advertise-routes, useRoutingFeatures) based on role assignment in nodes.nix.
**Verify:** Check `config/nodes.nix` for role assignment

## Kubernetes Deployment

### OCI Chart Hash Resolution
**Lesson:** When adding new OCI Helm charts, use a placeholder hash (32 zeros) and let `make manifests` fail with the correct hash in the error message.
**Context:** Kubenix requires exact SHA256 hashes; multiple format attempts failed until getting from error output.
**Verify:** Check error output: `wanted: sha256-...`

### CloudPirates Keycloak Secret Keys
**Lesson:** CloudPirates Keycloak chart requires lowercase secret keys: `db-username`, `db-password`, `KEYCLOAK_ADMIN_PASSWORD`.
**Context:** Chart validation fails with uppercase keys like `DB_USERNAME` or `DB_PASSWORD`.
**Verify:** Check chart values.yaml for required key format.

### StatefulSet Updates
**Lesson:** Kubernetes StatefulSets forbid updates to most fields. Use `kubectl delete statefulset <name> -n <ns> --cascade=orphan` then `flux reconcile` to recreate.
**Context:** Standard updates fail with "Forbidden: updates to statefulset spec for fields other than...".
**Verify:** State recreates successfully with new spec.

### SOPS Secrets Must Be Verified Before Manifest Generation
**Lesson:** After adding/modifying `secrets/k8s-secrets.enc.yaml`, verify key exists: `sops -d secrets/k8s-secrets.enc.yaml | grep <key>` before `make manifests`.
**Context:** vals injection during `make vmanifests` fails if secret keys are missing, causing cryptic manifest generation errors. Subagent claims aren't always verified.
**Verify:** `sops -d secrets/k8s-secrets.enc.yaml | grep <key>` returns expected value

## Mautrix Bridge Configuration

### Bridge Config Structure Varies by Type
**Lesson:** mautrix-whatsapp uses root-level `database:`, but mautrix-discord requires `appservice.database:` (nested). Check upstream example-config.yaml for each bridge.
**Context:** Different mautrix bridges have different config schemas. Discord fails with "appservice.database not configured" if database is at root level.
**Verify:** Compare `database:` placement in generated config against upstream example-config.yaml

### Never Use Placeholder Values for Secrets
**Lesson:** Always use `kubenix.lib.secretsInlineFor "key_name"` in Nix configs, never hardcode "REPLACE_ME" or other placeholders.
**Context:** Placeholders bypass the vals/SOPS injection pipeline and end up literally in the generated YAML, causing auth failures.
**Verify:** `grep -r "REPLACE_ME\|PLACEHOLDER" modules/kubenix/apps/` should return nothing before committing

### Underscore Prefix Disables Kubenix Modules
**Lesson:** Files prefixed with `_` (e.g., `_mautrix-discord.nix`) are ignored by kubenix. Rename to enable: `git mv _file.nix file.nix`.
**Context:** Kubenix ignores `_*` files to allow WIP/disabled modules. Forgotten underscore = missing deployment.
**Verify:** `ls modules/kubenix/apps/*.nix | grep -v "^_"` shows all active modules

### mautrix-discord Bot Token Login Process
**Lesson:** Unlike WhatsApp bridge, mautrix-discord requires interactive login via Matrix - the bot token cannot be pre-configured in the config file.
**Context:** The Discord bot token (`mautrix_discord_bot_token`) is stored in SOPS for reference but must be provided interactively. After deployment, users must:
1. Create a Discord bot at https://discord.com/developers/applications
2. Enable "Server Members Intent" and "Message Content Intent" under Privileged Gateway Intents
3. Copy the bot token
4. In Matrix, start a DM with `@discordbot:josevictor.me`
5. Send: `login bot <token>`
**Verify:** Bridge shows as "connected" in pod logs after login

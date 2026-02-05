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
**Lesson:** `make check` evaluates the flake from git state. New files must be `git add`-ed before validation.
**Context:** Nix flakes are pure and use git to determine the source tree. Unstaged files are invisible to `nix flake check`.
**Verify:** `git status` - ensure new files are staged

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

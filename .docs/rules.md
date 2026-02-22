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

### Use `sops --set` to Add Keys to Encrypted Files
**Lesson:** Never decrypt→edit→re-encrypt SOPS files (`sops -d > plain && edit && sops -e plain > enc`). This corrupts encryption metadata. Use `sops --set '["key"] "value"' secrets/file.enc.yaml` to add keys in-place.
**Context:** Re-encrypting with `sops -e` produces different metadata/MAC, corrupting the file. `sops --set` modifies atomically.
**Verify:** `sops -d secrets/file.enc.yaml | grep <new_key>` returns expected value after `--set`

### SOPS Secrets Must Be Verified Before Manifest Generation
**Lesson:** After adding/modifying `secrets/k8s-secrets.enc.yaml`, verify key exists: `sops -d secrets/k8s-secrets.enc.yaml | grep <key>` before `make manifests`.
**Context:** vals injection during `make vmanifests` fails if secret keys are missing, causing cryptic manifest generation errors. Subagent claims aren't always verified.
**Verify:** `sops -d secrets/k8s-secrets.enc.yaml | grep <key>` returns expected value

### Kubenix Secrets for Environment Variables Require Explicit Definition
**Lesson:** When adding env vars with `valueFrom.secretKeyRef`, the key must be explicitly defined in the kubenix Secret config (e.g., `*-config.enc.nix`) using `kubenix.lib.secretsFor`, not just exist in `secrets/k8s-secrets.enc.yaml`.
**Context:** `kubenix.lib.secretsInlineFor` injects into JSON configs, but `valueFrom.secretKeyRef` reads from K8s Secret resources. The key must be declared in both places: source secrets file AND kubenix Secret definition.
**Verify:** Check generated manifest: `sops -d .k8s/apps/<app>-config.enc.yaml | grep <KEY_NAME>`

## Mautrix Bridge Configuration

### Bridge Config Structure Varies by Type
**Lesson:** mautrix-whatsapp uses root-level `database:`, but mautrix-discord requires `appservice.database:` (nested). mautrix-slack uses bridgev2 format with `database:` at root level but `username_template:` moved from appservice to root.
**Context:** Different mautrix bridges have different config schemas. Slack fails with "Legacy bridge config detected" if using pre-bridgev2 structure. Generate example config from bridge image first.
**Verify:** Generate with `docker run --rm dock.mau.dev/mautrix/slack:latest -e` then compare structure to generated config

### Never Use Placeholder Values for Secrets
**Lesson:** Always use `kubenix.lib.secretsInlineFor "key_name"` in Nix configs, never hardcode "REPLACE_ME" or other placeholders.
**Context:** Placeholders bypass the vals/SOPS injection pipeline and end up literally in the generated YAML, causing auth failures.
**Verify:** `grep -r "REPLACE_ME\|PLACEHOLDER" modules/kubenix/apps/` should return nothing before committing

### Underscore Prefix Disables Kubenix Modules
**Lesson:** Files prefixed with `_` (e.g., `_mautrix-discord.nix`) are ignored by kubenix. Rename to enable: `git mv _file.nix file.nix`.
**Context:** Kubenix ignores `_*` files to allow WIP/disabled modules. Forgotten underscore = missing deployment.
**Verify:** `ls modules/kubenix/apps/*.nix | grep -v "^_"` shows all active modules

## NixOS Systemd Services

### Systemd PATH Is Minimal — Explicitly Declare All Binary Dependencies
**Lesson:** NixOS systemd services have a stripped PATH. If a script calls a tool indirectly (e.g., `mc` calls `getent`), add the transitive dependency to `path = [ pkgs.getent ]`. Always test with a deploy, not just `make check`.
**Context:** `mc` (minio-client) calls `getent` internally to resolve home dir. `pkgs.getent` is a separate package from `glibc.bin` on aarch64. `make check` won't catch missing runtime PATH deps.
**Verify:** After deploy: `journalctl -u <service> --no-pager | grep -i "not found\|error"`

### MinIO Client (`mc`) CLI Flags Vary by Version
**Lesson:** Always check `mc <subcommand> --help` on the target host before scripting `mc` commands. Flags like `--id` for `mc ilm rule add` don't exist in all versions; use only what `--help` confirms.
**Context:** `mc ilm rule add --id expire-14d --expire-days 14` fails silently (unknown flag). The correct form is `mc ilm rule add --expire-days 14 pi/bucket`.
**Verify:** `ssh root@<host> 'mc <subcommand> --help'` before writing bootstrap scripts

## Mautrix Bridge Configuration

### mautrix-discord Bot Token Login Process
**Lesson:** Unlike WhatsApp bridge, mautrix-discord requires interactive login via Matrix - the bot token cannot be pre-configured in the config file.
**Context:** The Discord bot token (`mautrix_discord_bot_token`) is stored in SOPS for reference but must be provided interactively. After deployment, users must:
1. Create a Discord bot at https://discord.com/developers/applications
2. Enable "Server Members Intent" and "Message Content Intent" under Privileged Gateway Intents
3. Copy the bot token
4. In Matrix, start a DM with `@discordbot:josevictor.me`
5. Send: `login bot <token>`
**Verify:** Bridge shows as "connected" in pod logs after login

## ProtonMail Bridge Deployment

### Password Store Initialization Required
**Lesson:** ProtonMail Bridge requires `pass` password manager initialized with GPG key before first run. Add an init container to generate GPG key and run `pass init`.
**Context:** The bridge stores credentials using `pass` which needs a GPG key. Without initialization, bridge fails with "pass not initialized: exit status 1: Error: password store is empty."
**Verify:** Init container logs show "pass initialized successfully" and bridge logs show "Generating bridge vault key"

### Auto-Updated Binary Requires Runtime Dependencies
**Lesson:** ProtonMail Bridge auto-updates on first run, potentially requiring libraries not in base image. Check logs for "error while loading shared libraries" and install missing packages in main container (not init container).
**Context:** Bridge v3.19 auto-updated to v3.22 requiring `libfido2.so.1`. Init containers have separate filesystems - libraries must be installed in main container where bridge actually runs.
**Verify:** `kubectl logs` shows successful startup without library errors; `ldd /protonmail/proton-bridge` shows all libraries resolved

### Enable TTY/Stdin for Interactive CLI Access
**Lesson:** Containers running interactive CLIs need `tty: true` and `stdin: true` in spec to support `kubectl attach` or exec-based interaction.
**Context:** Without TTY enabled, `kubectl attach` fails with "container did not allocate one" and interactive commands don't work properly.
**Verify:** `kubectl attach -it <pod>` provides interactive prompt; check `kubectl get pod <pod> -o yaml | grep -A2 "tty:"`

## Flux GitOps

### Flux Kustomize Failures Require Manual Intervention
**Lesson:** When Flux kustomize fails with duplicate resource errors, use `kubectl apply -f <manifest>` directly instead of waiting for GitOps reconciliation.
**Context:** Flux may fail with "may not add resource with an already registered id" errors due to kustomization issues. Manual apply bypasses the problem while keeping manifests in git.
**Verify:** `kubectl get pod -n <ns>` shows resources running after manual apply

## Velero Backup Configuration

### Velero BSL Updates Require Recreation
**Lesson:** When changing BackupStorageLocation fields (like region or bucket), delete the BSL CR to force recreation: `kubectl delete bsl default -n velero`.
**Context:** Kubernetes/Velero often ignores updates to existing BSLs or fails to reload them properly.
**Verify:** `kubectl get bsl default -n velero -o yaml` matches new config.

### MinIO S3 Client Compatibility
**Lesson:** Always set `s3ForcePathStyle: true` and a valid region (e.g. `minio` or `us-east-1`) when using MinIO as target.
**Context:** Without explicit path style and region, the AWS SDK used by Velero fails to connect to MinIO.
**Verify:** `kubectl get bsl default -n velero -o yaml` shows `s3ForcePathStyle: true`.

### Enable Kopia for Filesystem Backups
**Lesson:** To enable PVC filesystem backups, explicitly set `deployNodeAgent: true` in Velero Helm chart values.
**Context:** Default chart values may disable the node agent (formerly Restic daemonset), preventing FS backups.
**Verify:** `kubectl get pods -n velero -l name=node-agent` shows running pods.

## Kubernetes Container Security

### runAsNonRoot Fails with Non-Numeric Users
**Lesson:** Don't use `runAsNonRoot: true` when container images use non-numeric users. Kubernetes can't verify string usernames (like `flaresolverr`) are non-root. Instead use `allowPrivilegeEscalation: false` + `capabilities: { drop = [ "ALL" ]; }`.
**Context:** FlareSolverr image uses user `flaresolverr` (not UID 1000). Setting `runAsNonRoot: true` causes `CreateContainerConfigError: cannot verify user is non-root`.
**Verify:** Check `kubectl describe pod` shows `CreateContainerConfigError` with message about non-numeric user.

## Prometheus & Grafana Monitoring

### Query Prometheus Directly via kubectl exec, Not Grafana MCP
**Lesson:** Grafana MCP `query_prometheus` has broken time format parsing. Use `kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=<promql>'` instead.
**Context:** MCP rejects all time formats ("now", unix timestamps). Direct Prometheus API via kubectl exec is reliable and faster.
**Verify:** `kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=up'`

### Cross-Architecture NixOS Deploy to Pi (aarch64)
**Lesson:** Cannot cross-compile x86_64→aarch64 via `nixos-rebuild --target-host`. SSH into the Pi and rebuild from GitHub: `ssh root@10.10.10.209 "nixos-rebuild switch --flake github:josevictorferreira/homelab#lab-pi-bk"`.
**Context:** `--target-host` tries to build locally (wrong arch). `--build-host` on Pi via local flake path also fails. Pi must build natively from a remote flake ref.
**Verify:** `ssh root@10.10.10.209 "nixos-rebuild switch --flake github:josevictorferreira/homelab#lab-pi-bk"` completes without arch errors

## Postgres Backup & Restore Drill

### Use Trust Auth for Ephemeral Scratch Postgres
**Lesson:** Always use `ALLOW_EMPTY_PASSWORD=yes` + `POSTGRESQL_ENABLE_TRUST_AUTH=yes` for scratch/ephemeral Bitnami postgres. `pg_dumpall` includes `ALTER ROLE postgres WITH PASSWORD` which changes the scratch password mid-restore, breaking subsequent `\connect` commands. Trust auth eliminates all password issues. `ALLOW_EMPTY_PASSWORD` is required separately for Bitnami entrypoint to start.
**Context:** Three approaches failed before trust auth: scratch-only password (breaks after ALTER ROLE), prod password (breaks initial connect), ON_ERROR_STOP removal (masks real errors).
**Verify:** Check scratch-postgres container env has both `ALLOW_EMPTY_PASSWORD=yes` and `POSTGRESQL_ENABLE_TRUST_AUTH=yes`

### Size activeDeadlineSeconds for Large SQL Restores
**Lesson:** For `pg_dumpall` restore jobs, set `activeDeadlineSeconds` to 3x the expected restore time. A 1.5 GiB uncompressed dump takes ~25-30 min on emptyDir-backed scratch postgres. Current setting: 2700s (45min).
**Context:** 1200s (20min) caused DeadlineExceeded on a job that was actively restoring successfully. Waiting 20+ min only to hit a timeout wastes significant debugging time.
**Verify:** `grep activeDeadlineSeconds modules/kubenix/apps/postgres-restore-drill.nix` — should be ≥ 2700

## Nix OCI Image Building

### Use buildImage for Podman Compatibility
**Lesson:** Prefer `dockerTools.buildImage` over `streamLayeredImage` for podman. `buildImage` produces a tarball that loads directly with `podman load < result`. `streamLayeredImage` produces a streaming script that can timeout or fail with podman.
**Context:** Both work with Docker, but podman handles tarballs more reliably than streaming scripts.
**Verify:** `file result` shows "gzip compressed data" not "POSIX shell script"

### Copy Custom Files in extraCommands, Not pathsToLink
**Lesson:** When using `buildImage`, manually copy entrypoint scripts and config templates in `extraCommands` using `cp`. Don't rely on `pathsToLink` to include `/`.
**Context:** `pathsToLink` only affects symlinking from derivation outputs, not ad-hoc files. Custom files need explicit `cp` commands in `extraCommands`.
**Verify:** `podman run --rm --entrypoint "" <image> ls -la /entrypoint.sh /etc/openclaw/`

### Include ALL Runtime Dependencies in OCI Image PATH
**Lesson:** Container entrypoints need ALL binaries in the image PATH. Commonly missed: `gnused` (for shell scripts), `coreutils` (for basic commands). Test with `podman exec <container> which sed`.
**Context:** Unlike NixOS where PATH is managed by the system, containers only have what you explicitly include. A shell script using `sed` will fail if `gnused` isn't in the derivation.
**Verify:** `podman run --rm --entrypoint "" <image> sh -c 'which sed && which cat && which ls'`

### FOD npm Builds Need Sandbox Bypass
**Lesson:** `buildNpmPackage` with network access requires `__noChroot = true;` which needs `nix.extraOptions = "allow-dirty = true"` in nix.conf. For CI/pure builds, use placeholder hash and update from error message (like OCI charts).
**Context:** Nix sandbox blocks network. FOD derivation with `__noChroot` fails with "disabled in 'allowed-impure-functions' settings" unless explicitly allowed.
**Verify:** Build error shows "hash mismatch" (expected) or "network access denied" (need sandbox bypass)

### OpenClaw Matrix Extension Has Empty node_modules
**Lesson:** nix-openclaw bundles extensions at `/lib/openclaw/extensions/` but `node_modules` directories are EMPTY. Matrix plugin requires 5 npm packages (matrix-bot-sdk, matrix-sdk-crypto-nodejs, markdown-it, music-metadata, zod) - must pre-install in image.
**Context:** Unlike WhatsApp which bundles deps in core (Baileys), Matrix uses external packages with native bindings. Runtime npm install would break `--network=none` operation.
**Verify:** `ls /lib/openclaw/extensions/matrix/node_modules` - if empty, deps missing

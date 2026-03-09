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

### Kubenix Files Are Evaluated Independently — No Cross-File Module State
**Lesson:** Each `.nix` file in `modules/kubenix/` is evaluated via a separate `evalModules` call in `default.nix` (lines 48-58). Files do NOT share NixOS module state. To share resources (e.g., ConfigMap defined in `.enc.nix`, mounted in `.nix`), define as plain `kubernetes.resources.configMaps` in the `.enc.nix` file and reference via persistence/volumes in the main `.nix` file.
**Context:** Attempting to set `submodules.instances.X.args.config` from a different file broke the build. The correct pattern follows `searxng-config.enc.nix`, `blocky-config.enc.nix`.
**Verify:** `grep "evalModules" modules/kubenix/default.nix` — each file gets its own evaluation context.

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

### Use mkDerivation Not buildEnv for Writable OCI Rootfs
**Lesson:** When building OCI images that need runtime file modifications (like adding node_modules), use `mkDerivation` with `cp -rL` instead of `buildEnv`. `buildEnv` creates symlink trees to read-only nix store paths.
**Context:** `buildEnv` is great for PATH construction but creates read-only symlinks. For writable rootfs layers, use `mkDerivation` + `cp -rL` + `chmod -R u+w`.
**Verify:** `ls -la <path>` shows real files not symlinks to `/nix/store/`

### Dereference Nix Store Paths with cp -rL
**Lesson:** When copying from nix store derivations, use `cp -rL` (dereference) not `cp -rsf`. The `-s` flag creates symlinks, not actual copies, making files read-only.
**Context:** `cp -rsf /nix/store/.../lib ./lib` creates symlinks pointing back to nix store. Use `cp -rL` to dereference and create writable copies, then `chmod -R u+w` to enable modification.
**Verify:** `stat <file>` shows regular file, not symlink; can `touch <file>` without permission error

## Kubenix Resource Generation

### Kubenix Resource Types Need Explicit Namespace for Namespaced Resources
**Lesson:** When defining namespaced resources (ResourceQuota, LimitRange, etc.) in kubenix, always set `metadata.namespace`. Kubenix doesn't automatically infer namespace from the attribute name.
**Context:** Resources without explicit namespace get `namespace: null` in generated YAML, causing kustomize "already registered id" errors or "namespace not specified" errors from the API server.
**Verify:** Check generated YAML has `metadata.namespace` set: `grep -A5 "kind: ResourceQuota" .k8s/bootstrap/resource-quotas.yaml | grep namespace`

## Release Submodule (app-template)

### Release Submodule Requires LoadBalancer Service Entry
**Lesson:** The release submodule unconditionally calls `kubenix.lib.serviceAnnotationFor` for every app. Even when using ClusterIP (via `values.service.main.type = "ClusterIP"`), the service name must exist in `homelab.kubernetes.loadBalancer.services` or Nix evaluation fails.
**Context:** The annotation lookup happens eagerly during evaluation before values merge. The workaround: add an IP entry to the loadBalancer map even for ClusterIP-only services.
**Verify:** Add entry in `config/kubernetes.nix` loadBalancer.services before running `make manifests`

### Persistence Schema Requires Full Fields Even When Disabled
**Lesson:** When disabling the release submodule's default persistence, don't pass minimal `{ enabled = false; }`. The bjw-s chart v4 validates `persistence.main` against a schema that requires fields like `type`, `storageClass` even when disabled.
**Context:** Either omit the `persistence` argument entirely (uses default with `enabled = false` + all fields) or don't fight it and add extra persistence volumes via `values.persistence.*`.
**Verify:** `nix build .#gen-manifests` fails with "oneOf" schema validation if persistence is malformed

### Use advancedMounts to Scope Volumes to Specific Containers
**Lesson:** The release submodule's default persistence uses `globalMounts` which mounts to ALL containers including sidecars. Use `advancedMounts` to restrict volumes to specific containers (e.g., only main container, not tailscale sidecar).
**Context:** Tailscale sidecar shouldn't get /config, /state, /logs, or workspace mounts. Structure: `advancedMounts.<controller>.<container> = [{ name = "..."; path = "..."; }]`. Global mounts on tailscale-only volumes (dev-tun, tailscale-state) are fine.
**Verify:** Check generated Deployment YAML - tailscale container should only have its own mounts, not main container's data volumes

## OpenClaw Version Upgrade

### Provide Missing Build Tools via npm Tarball Derivations
**Lesson:** When a Nix build needs a tool that uses `pnpm dlx` (network-dependent), check if the build script has a `command -v <tool>` fallback. If yes, create a Nix derivation from pre-built npm tarballs (main + native binding + deps) and add it to `nativeBuildInputs`. Fetch tarball URLs/hashes from `registry.npmjs.org/<pkg>/<version>`.
**Context:** OpenClaw v2026.2.22+ needs rolldown for `canvas:a2ui:bundle`. `pnpm dlx rolldown` fails in sandbox. `bundle-a2ui.sh` checks `command -v rolldown` first — providing the binary in PATH avoids network entirely. Pattern: `fetchurl` 4 tarballs → assemble `node_modules` tree → `makeWrapper` for CLI.
**Verify:** `nix build .#openclaw-nix-image` succeeds; check logs for `canvas:a2ui:bundle` completing without `pnpm dlx`

### Verify Image Push — `make push-openclaw` Has Tag Mismatch
**Lesson:** `make push-openclaw` tags `localhost/openclaw-nix:dev` but the stream creates `:v{version}`. This silently pushes a STALE `:dev` image. Always push manually: `podman tag localhost/openclaw-nix:v{VERSION} ghcr.io/.../openclaw-nix:latest && podman push ghcr.io/.../openclaw-nix:latest`.
**Context:** The tag mismatch in `modules/commands.nix` (`LOCAL_TAG = ...dev`) means `podman tag` targets a non-existent or old image. All verification passes locally but the cluster pulls the wrong image.
**Verify:** After push: `podman images | grep openclaw` — confirm GHCR tag's IMAGE ID matches the `:v{VERSION}` tag, not `:dev`

### Use Named let Bindings Not srcs for Multi-Tarball Derivations
**Lesson:** In `mkDerivation`, don't use `srcs = [...]` + `builtins.elemAt srcs N` in build scripts. Instead, define each `fetchurl` as a named `let` binding and reference it directly in shell via `${tgzName}` interpolation.
**Context:** `builtins.elemAt` is a Nix-level function, not available in bash. `srcs` is auto-unpacked. Named bindings give you stable references: `tar xzf ${rolldownTgz} -C $out/...`.
**Verify:** `nix eval` the derivation successfully; no `undefined variable` errors

### streamLayeredImage: Use extraCommands to Merge /bin/ Across Contents
**Lesson:** `streamLayeredImage` `contents` entries that both provide `/bin/` don't merge — Docker overlay layers mean last writer wins. Use `pkgs.buildEnv` for all CLI tools + `extraCommands` to symlink `${buildEnv}/bin/*` into `./bin/`. The `buildEnv` must be in `contents` so its closure is included.
**Context:** Spent 60+ min debugging "missing tools" that were in the image's nix store but not in `/bin/`. The customization layer (from `extraCommands`) sits on top and reliably provides symlinks.
**Verify:** `tar tf /nix/store/*-customisation-layer/layer.tar | grep './bin/grep'` shows symlink in top layer

### Don't Remove App Binaries When Refactoring Image /bin/
**Lesson:** When refactoring OCI image `/bin/` construction (e.g., moving tools to `buildEnv`), ensure the main app binary (`openclaw`) is still explicitly added to rootfs `/bin/` via symlink or copy.
**Context:** Moving all packages to `buildEnv` and removing the rootfs bin loop also removed the `openclaw` binary, causing `exec: openclaw: not found` crash.
**Verify:** `podman run --rm --entrypoint '' <image> which openclaw` returns a path before pushing

### OpenClaw Config: `dangerouslyAllowHostHeaderOriginFallback` Required for Non-Loopback
**Lesson:** The `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback` config is REQUIRED when binding gateway to non-loopback addresses (e.g., `bind: "lan"`), despite being flagged as an "unknown config key" by the doctor.
**Context:** OpenClaw v2026.2.25+ enforces origin validation for Control UI. The doctor warns about the key being unrecognized, but the gateway fails to start without it on non-loopback binds. Do NOT remove this config.
**Verify:** Gateway starts without `Error: non-loopback Control UI requires gateway.controlUi.allowedOrigins` error.


### Use Explicit Version Tags Instead of `latest` for K8s Images
**Lesson:** Use specific version tags (e.g., `2026.2.25`) instead of `latest` for container images deployed to Kubernetes. Node-level image caching causes `latest` to stay stale even with `imagePullPolicy: Always`.
**Context:** Kubernetes nodes cache images tagged as `latest`. A rollout restart doesn't force a fresh pull if the node thinks it already has `latest`. Using explicit tags ensures the correct version is deployed.
**Verify:** `kubectl get pod <pod> -o yaml | grep imageID` shows the expected digest for the version tag.

## Synapse S3 Media Storage

### Synapse Media Path is /synapse/data/media
**Lesson:** Synapse stores media at `/synapse/data/media` NOT `/data/media_store`. Check the actual mount before planning migrations.
**Context:** The matrix-synapse chart uses /synapse/data as the data directory, not /data. Migration scripts will fail if given wrong path.
**Verify:** `kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- ls -la /synapse/data/media/`

### Runtime Pip Install Requires psycopg2-binary
**Lesson:** When installing synapse-s3-storage-provider at runtime, install `psycopg2-binary` separately before the provider package to avoid compilation errors.
**Context:** The container lacks build tools for psycopg2. Use `pip install boto3 psycopg2-binary` then `pip install --no-deps synapse-s3-storage-provider`.
**Verify:** Check pod logs for "Failed to build psycopg2" - should not appear.

### s3_media_upload Script Not Installed with --no-deps
**Lesson:** Using `--no-deps` when installing synapse-s3-storage-provider skips the `s3_media_upload` console script. Download it manually from GitHub or install without --no-deps into a separate directory.
**Context:** The migration script is defined as an entry point and isn't copied when using --no-deps. Must be available at `/modules/s3_media_upload` or downloaded separately.
**Verify:** `kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- python /modules/s3_media_upload --help`

### s3_media_upload Only Migrates DB-Tracked Files — Use Direct S3 Sync for Pre-Existing Media
**Lesson:** `s3_media_upload` only uploads files tracked in the Synapse database. For media predating the S3 provider (existing on PVC), use direct `aws s3 sync` instead.
**Context:** The script queries the DB for media to upload — if files exist on disk but aren't in the DB's media tracking tables, they're skipped. Direct S3 sync bypasses this: `aws s3 sync /synapse/data/media/local_content s3://bucket/local_content/ --endpoint-url=...`
**Verify:** After `s3_media_upload update`, check cache.db row count — if 0 but files exist on disk, use direct sync instead.

### Helm Test Pods Are Ephemeral — Ignore Failures for Running Apps
**Lesson:** Pods with `helm.sh/hook: test-success` are one-time validation jobs, not ongoing health checks. Failed test pods don't indicate app problems.
**Context:** The `synapse-matrix-synapse-test-connection` pod failed due to busybox wget issues, but Synapse itself was healthy. Delete stale test pods: `kubectl delete pod <name>-test-connection -n <ns>`
**Verify:** Check app deployment status separately from test pod status.

## K3s Bootstrap Resources

### K3s Addon Controller Manages Bootstrap Manifests from Init Node
**Lesson:** Changes to bootstrap resources (ResourceQuota, LimitRange, etc.) cannot be applied via `kubectl` — K3s's `objectset.rio.cattle.io` controller will revert them. Must redeploy NixOS to the init node (`lab-alpha-cp`) to update manifests in `/var/lib/rancher/k3s/server/manifests/`.
**Context:** K3s auto-deploys manifests from the init node's filesystem. The controller continuously reconciles these files, overwriting any kubectl changes. Check managed fields: `kubectl get <resource> -o yaml | grep "objectset.rio.cattle.io"`.
**Verify:** After NixOS deploy, check init node: `ssh root@lab-alpha-cp 'cat /var/lib/rancher/k3s/server/manifests/resource-quotas.yaml'`

### `.k8s/` Directory is NOT in Git — K3s Auto-Deploy Only
**Lesson:** The `.k8s/` directory is `.gitignore`d and generated locally via `make manifests`. Flux/K3s does NOT reconcile from these files for bootstrap resources. Only the source Nix files matter.
**Context:** Bootstrap manifests are deployed by K3s's auto-deploy mechanism from the init node's filesystem, not by Flux. Changes must be made to `modules/kubenix/bootstrap/*.nix` and deployed via NixOS rebuild.
**Verify:** `cat .gitignore | grep "^\.k8s"` — should be ignored; check `modules/profiles/k8s-control-plane.nix` for K3s manifest deployment logic.

## Kubernetes Operations

### ResourceQuota Debugging — Check Per-Pod Limits
**Lesson:** When pods fail with "exceeded quota" errors, audit actual per-pod CPU/memory limits with: `kubectl get pods -n <ns> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits.cpu}{"\n"}{end}'`. Aggregate quota used/limited values hide which specific pods are over-provisioned.
**Context:** Default container limits (500m CPU, 512Mi memory) silently apply to sidecars like gluetun VPN, exportarr, config-reloaders, quickly exhausting namespace quotas.
**Verify:** Sum of all container limits across namespace should be < quota hard limits. Use `kubectl get resourcequota -n <ns> -o yaml` to see used vs hard.

### Always Verify kubectl Context Before Cluster Operations
**Lesson:** Run `kubectl config current-context` before any cluster operations. Multi-cluster environments (EKS + k3s) make it easy to operate on the wrong cluster.
**Context:** Ran commands against AWS EKS instead of homelab k3s for significant time. The contexts look similar in output but target completely different infrastructure.
**Verify:** `kubectl config current-context` matches expected cluster name before proceeding.

### RWO PVCs + GitOps Auto-Scale = Conflict — Suspend Flux for Manual Ops
**Lesson:** When manually mounting a ReadWriteOnce PVC (e.g., for migration jobs), GitOps controllers will auto-scale deployments back up, causing PVC mount conflicts.
**Context:** Scaled down Synapse to free PVC for migration, but Flux auto-scaled it back up. Either suspend the Flux Kustomization (`flux suspend kustomization <name>`) or accept the race condition and retry.
**Verify:** After scaling down: `flux suspend kustomization apps -n flux-system` before starting manual PVC operations.

## Podman OCI Image Management

### Podman Push Silently Pushes Stale Image Due to GHCR Tag Collision
**Lesson:** After `podman tag localhost/image:tag ghcr.io/.../image:tag`, a subsequent `podman pull ghcr.io/...` (e.g., to verify) overwrites the local GHCR tag with the REMOTE stale version. Always: (1) `podman rmi ghcr.io/...` to clear cached tag, (2) `podman tag localhost/...` to retag from local, (3) verify image ID with `podman images`, (4) push with `--format oci`.
**Context:** Pushed openclaw-nix image that appeared correct but cluster pulled a stale version because podman's local GHCR tag pointed to the remote's old manifest, not the locally built image.
**Verify:** `podman images | grep <ghcr-tag>` — IMAGE ID must match `localhost/` build before pushing.

### Trace Full imageTag Computation Before Changing Version Strings
**Lesson:** When bumping container image versions, trace the full tag computation chain (`version` → `imageTag` → pushed tag → K8s manifest tag). Changing version in one place without understanding the formula can produce unexpected tags like `v2026.3.2-v2-v2` (double suffix).
**Context:** Changed `version = "2026.3.2-v2"` but `imageTag = "v${version}-v2"` produced `v2026.3.2-v2-v2`. Must `grep -n 'imageTag\|version\|Tag'` across all files to trace the full chain.
**Verify:** `grep -rn 'imageTag\|openclawVersion\|image.tag' oci-images/ modules/` — ensure no double-suffix in computed tag.

### Force Delete Pods Stuck Terminating During Large Image Pulls
**Lesson:** When a rollout restart kills a pod mid-pull of a large image (6GB+), the pod gets stuck in `Terminating` state and no new pod is created (all ReplicaSets show DESIRED=0). Fix: `kubectl delete pod <name> -n <ns> --force --grace-period=0`, then a new pod is automatically created.
**Context:** Rollout restart of openclaw-nix (6GB image) caused pod stuck Terminating for 10+ minutes. All 5 ReplicaSets showed DESIRED=0, CURRENT=0. Force-deleting the stuck pod allowed the new ReplicaSet to create a fresh pod.
**Verify:** After force delete: `kubectl get pods -n <ns> -l app.kubernetes.io/name=<app>` shows new pod in ContainerCreating/Running state.

## Git History & Secret Scrubbing

### `git-filter-repo` Replaces Strings in Working Tree Source Files
**Lesson:** `git-filter-repo --replace-text` rewrites ALL commits including HEAD, modifying source files in the working tree. After scrubbing, check source files for the replacement string and fix them (e.g., replace `REDACTED_X` with proper env var reference `${X}`), then re-run `make manifests`.
**Context:** Scrubbing a leaked ElevenLabs key replaced it with `REDACTED_ELEVENLABS_KEY` in `openclaw-config.enc.nix` source code, which then propagated to generated YAML. Required manual fix + regeneration.
**Verify:** `grep -r "REDACTED" modules/kubenix/` should return nothing after fixing.

### Never Use `sed` Secret Substitution in Kubernetes Entrypoints
**Lesson:** Never use `sed -i "s/\${VAR}/$VAR/g"` in container entrypoint scripts defined in Nix/YAML manifests. The shell interpolation can leak actual secret values into non-encrypted `.k8s/*.yaml` files at generation time. Instead, let the application resolve `${VAR}` from env vars at runtime, or mount secrets via Kubernetes Secret volumes.
**Context:** An ElevenLabs API key was committed to `openclaw-nix.yaml` (non-encrypted) because `sed` substituted the env var with its real value during manifest generation. Required key rotation + git history scrub.
**Verify:** `grep -rn "sed.*secretKeyRef\|sed.*printenv\|sed.*\\\$" modules/kubenix/apps/*.nix` should return nothing.

### Nix String Newlines Break Container Images
**Lesson:** When defining container image strings in Nix, ensure the closing quote is on the SAME line as the content. A trailing newline in the string (e.g., closing quote on a new line) adds `\n` to the image tag, causing "Invalid value: must not have leading or trailing whitespace" errors.
**Context:** Velero init container image had closing quote on separate line: `image = "velero/velero-plugin-for-aws:v1.13.2@sha256:...\n";` — the `\n` broke the deployment.
**Verify:** `grep -n 'image = ' modules/kubenix/**/*.nix | grep -v ';$'` — ensure all image strings end with `;` on same line.

## Flux GitOps

### Flux Reconciles from Git, Not Local Files
**Lesson:** `flux reconcile` and `make reconcile` only sync from the git repository, not local `.k8s/` files. For immediate fixes, use `sops -d .k8s/<path>/<secret>.enc.yaml | kubectl apply -f -` to apply decrypted secrets directly.
**Context:** Ran Flux reconciliation commands expecting local manifest changes to apply, but Flux's source is the git repo. Local changes require commit+push OR manual kubectl apply.
**Verify:** After `flux reconcile`, check `kubectl get <resource>` — if unchanged, either commit to git or apply manually.

## Velero Backup

### BackupRepository Recovery After Clock Skew or Storage Outage
**Lesson:** If kopia maintenance jobs fail with "maintenance must be run by designated user" (often caused by clock skew or MinIO unavailability), delete the BackupRepository CR: `kubectl delete backuprepository <name> -n backup`. Velero will recreate it fresh.
**Context:** Pi downtime caused clock skew which corrupted kopia repository state. The error persisted even after MinIO recovered. Deleting the CR forces Velero to reinitialize the repository.
**Verify:** After deletion, check `kubectl get backuprepository -n backup` — should show new repository with recent creation timestamp.

### ResourceQuota CPU Contention in Backup Namespace
**Lesson:** Backup namespace has `limits.cpu: 2`. If multiple jobs run concurrently with 1 CPU limits each, they exhaust quota causing "exceeded quota" errors. Reduce backup job CPU limits to `500m` to allow concurrent operation.
**Context:** Velero backup pods (250m each), shared-subfolders-backup (1 CPU), and maintenance jobs all compete for the 2 CPU quota. Postgres backup jobs also use 500m.
**Verify:** `kubectl get resourcequota -n backup -o yaml` shows used vs hard limits; ensure sum of running job limits ≤ 2 CPU.

## Rook-Ceph Object Storage

### OBC "Ghost State" — Bound but RGW Empty
**Lesson:** When ObjectBucketClaims show `phase: Bound` but `radosgw-admin bucket list` returns empty, the Rook operator is in a stuck state. Fix: 1) Delete all OBCs and ObjectBuckets, 2) Restart rook-ceph-operator deployment, 3) Let Flux recreate OBCs.
**Context:** Operator marks OBCs Bound but fails to provision actual RGW buckets/users due to stale state or previous failures. Logs show "timeout waiting for RGW Admin API" errors.
**Verify:** After fix, `kubectl exec -n rook-ceph deploy/rook-ceph-tools -- radosgw-admin bucket list` shows buckets; `kubectl get objectbucket` shows OBs with matching bucket names.

### PVC Released State Blocks Rebinding
**Lesson:** When a PVC is stuck Pending with "volume already bound to a different claim", the PV is in `Released` state with a stale `claimRef`. Patch the PV to remove claimRef: `kubectl patch pv <name> --type=json -p='[{"op": "remove", "path": "/spec/claimRef"}]'`.
**Context:** Previous PVC deletion leaves claimRef pointing to deleted PVC, preventing new PVC from binding. Common with static CephFS volumes.
**Verify:** `kubectl get pv <name> -o jsonpath='{.spec.claimRef}'` returns empty; PVC should transition to Bound.
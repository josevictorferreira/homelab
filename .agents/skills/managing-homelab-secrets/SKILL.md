---
name: "managing-homelab-secrets"
description: "Manage SOPS-encrypted secrets, inject secrets into Kubenix manifests, and handle secret rotation in the homelab. Use when adding/editing keys in secrets/k8s-secrets.enc.yaml, configuring *-config.enc.nix files, or debugging secret injection in the manifest pipeline."
---

# Managing Homelab Secrets

Use this skill when adding, modifying, rotating, or referencing encrypted secrets in this homelab repository.

## Secrets Architecture

1. **Vault Source**: `secrets/k8s-secrets.enc.yaml` (cluster secrets) or `secrets/hosts-secrets.enc.yaml` (NixOS host secrets), encrypted with SOPS + age.
2. **Kubenix Binding**: `modules/kubenix/apps/<app>-config.enc.nix` defines Kubernetes Secret resources using `kubenix.lib.secretsFor` or inlines them with `kubenix.lib.secretsInlineFor`.
3. **Pipeline Ingestion**: `make manifests` runs `vals` to inject values from SOPS into `.k8s/apps/<app>-config.enc.yaml`, checks `manifests.lock`, and encrypts the output via SOPS before git commit.

---

## Gotchas & Rules

### 1. In-Place Edit with `sops --set` — Never Decrypt/Re-Encrypt
- **Rule**: Use `/etc/profiles/per-user/josevictor/bin/sops --set '["key"] "value"' secrets/k8s-secrets.enc.yaml` to add or update keys. Never do `sops -d > plain && edit && sops -e plain > enc`.
- **Why**: Decrypting to plaintext and re-encrypting with `sops -e` regenerates the data encryption key and changes metadata/MAC structures, corrupting the repository's SOPS configuration.
- **Verify**: `/etc/profiles/per-user/josevictor/bin/sops -d secrets/k8s-secrets.enc.yaml | grep "<new_key>"` returns the expected value.

### 2. Invoke `sops` via Absolute Binary Path (Bypass `rtk`)
- **Rule**: Always run `/etc/profiles/per-user/josevictor/bin/sops`, not plain `sops` or `rtk sops`.
- **Why**: The `rtk` wrapper command-line proxy truncates piped stdout to ~5KB. A full decrypt of `secrets/k8s-secrets.enc.yaml` via `rtk` drops ~75% of keys (showing 29 keys instead of 144+), misleading agents into thinking keys are missing.
- **Verify**: `/etc/profiles/per-user/josevictor/bin/sops -d secrets/k8s-secrets.enc.yaml | wc -l` prints the full line count (>180 lines).

### 3. Clear Stale `manifests.lock` and `.k8s/` File When Adding Keys
- **Rule**: When adding a new key to an existing `<app>-config.enc.nix`, delete that file's line from `manifests.lock` AND remove `.k8s/apps/<app>-config.enc.yaml` before running `make manifests`.
- **Why**: The `umanifests` stage compares the SHA256 of the new vals-injected file against `manifests.lock`. If the lockfile matches, it runs `git checkout -- <file>`, silently reverting to the git-committed version and dropping your newly added secret keys.
- **Verify**: `/etc/profiles/per-user/josevictor/bin/sops -d .k8s/apps/<app>-config.enc.yaml | grep "<NEW_KEY>"` shows the new key in the generated manifest.

### 4. Wire Secrets Explicitly in Both SOPS and Kubenix
- **Rule**: Adding a key to `secrets/k8s-secrets.enc.yaml` is step 1 of 2. For pods using `valueFrom.secretKeyRef`, you must declare the key in `<app>-config.enc.nix` with `kubenix.lib.secretsFor`.
- **Why**: `secretsFor "key"` emits a `ref+sops://...` pointer into the Kubernetes Secret manifest for `vals` to inject. If a pod references a Secret key that exists in SOPS but was omitted from `<app>-config.enc.nix`, Kubernetes pods fail to start with `CreateContainerConfigError`.
- **Verify**: Inspect generated decrypted manifest: `sops -d .k8s/apps/<app>-config.enc.yaml | grep "<KEY>"`.

### 5. `secretsFor` vs `secretsInlineFor` Selection
- **Rule**: Use `kubenix.lib.secretsFor "key"` for discrete Kubernetes Secret keys. Use `kubenix.lib.secretsInlineFor "key"` ONLY inside string templates (e.g. database DSNs, JSON/TOML configuration blobs).
- **Why**: `secretsFor` produces a Kubernetes Secret `stringData` attribute. `secretsInlineFor` directly substitutes the secret plaintext into configuration file text rendered inside the secret.
- **Verify**: If embedding into a URL: `DATABASE_URL = "postgresql://user:${kubenix.lib.secretsInlineFor "pw"}@host/db";`.

### 6. Never Use `sed` Secret Substitution in Entrypoints
- **Rule**: Never write `sed -i "s/\${KEY}/$KEY/g"` inside container entrypoints in Nix/Kubenix manifests.
- **Why**: Nix string interpolation parses `${KEY}` during manifest evaluation if unescaped, or shell execution during manifest generation can evaluate and bake real plaintext secrets into non-encrypted `.k8s/<app>.yaml` files (which leaked an ElevenLabs API key into git history).
- **Verify**: `grep -rn "sed.*secretKeyRef\|sed.*printenv" modules/kubenix/apps/` returns zero hits.

### 7. Enforce `.enc.nix` Extension for All Files Declaring Secrets
- **Rule**: Any file in `modules/kubenix/` that references secrets must be named `<name>-config.enc.nix`.
- **Why**: The manifest pipeline recognizes `.enc.nix` files to output `.enc.yaml` targets, which step 4 (`emanifests`) encrypts with SOPS. Files lacking `.enc.nix` output unencrypted `.yaml`, exposing credentials or failing git pre-commit secret scans.
- **Verify**: `git status` shows `.enc.yaml` generated in `.k8s/`, and `yq -e '.sops.mac' .k8s/apps/<name>-config.enc.yaml` confirms encryption.

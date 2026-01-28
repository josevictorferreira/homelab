# KUBENIX MODULE

Generates K8s manifests from Nix. All `.nix` files (except `_*` and `default.nix`) become YAML in `.k8s/`.

## CRITICAL SECURITY WARNING

### NEVER COMMIT AND PUSH UNENCRYPTED MANIFESTS OR FILES

This is a **CRITICAL SECURITY RULE** that must NEVER be violated:

1. **NEVER commit unencrypted secrets** - All secrets MUST be in `.enc.yaml` files and encrypted with SOPS
2. **NEVER commit unencrypted manifests** - The `.k8s/` directory contains generated manifests that may reference encrypted secrets
3. **NEVER commit `.nix` files with hardcoded secrets** - Use `kubenix.lib.secretsFor` for secret references only
4. **ALWAYS use `make manifests`** - This pipeline encrypts and properly handles secrets

### If You Accidentally Commit Unencrypted Secrets:

```bash
# Immediately remove the sensitive data
git reset --hard HEAD~1  # or use git reset to undo the commit
git push --force-with-lease  # only if already pushed
```

### Correct Secret Handling:

```nix
# GOOD - Uses encrypted secret reference
existingSecret = kubenix.lib.secretsFor "database-password";

# BAD - Never do this
password = "my-secret-password";  // NEVER commit actual secrets
```

## STRUCTURE

```
kubenix/
├── apps/          # Application deployments (see apps/AGENTS.md)
├── storage/       # Rook-Ceph operator, cluster, PVs
├── system/        # Cilium, cert-manager, GPU plugin
├── bootstrap/     # Cluster init manifests
├── monitoring/    # Prometheus, Grafana
├── _lib/          # Helper functions (not rendered)
├── _base.nix      # Shared module config
└── default.nix    # Discovery + renderer
```

## HOW IT WORKS

1. `default.nix` discovers all `.nix` files (excluding `_*` prefixed)
2. Each file → kubenix.evalModules → YAML
3. `make gmanifests` runs renderer → copies to `.k8s/`

## HELPER LIBRARY (`_lib/default.nix`)

```nix
kubenix.lib.secretsFor "key"           # ref+sops://secrets/k8s-secrets.enc.yaml#key
kubenix.lib.domainFor "app"            # app.{homelab.domain}
kubenix.lib.ingressFor "app"           # Full ingress config with TLS
kubenix.lib.ingressDomainFor "app"     # Simpler ingress (host-based)
kubenix.lib.plainServiceFor "app"      # LoadBalancer with Cilium annotations
kubenix.lib.serviceHostFor "svc" "ns"  # svc.ns.svc.cluster.local
kubenix.lib.toYamlStr data             # Convert attrset to YAML string
```

## CONVENTIONS

- Namespace: `homelab.kubernetes.namespaces.applications` (most apps)
- Ingress: `ingressClassName = "cilium"`, cert-manager cloudflare-issuer
- TLS: `secretName = "wildcard-tls"` (cluster-wide wildcard cert)
- Storage: `rook-ceph-block` for PVCs, `rook-ceph-objectstore` for S3

## CRITICAL: VERSION PINNING REQUIREMENT

When updating container images in kubenix modules, ALWAYS pin both the version tag AND the image digest (sha256). This ensures reproducible builds and prevents unexpected updates from registry changes.

### Correct Format

```nix
image = {
  registry = "ghcr.io";
  repository = "linkwarden/linkwarden";
  tag = "v2.13.5@sha256:9f1e69e11c36fcb94d97753479e76a7c66eabb4afd89c0ceb5ff52c0b1849ca5";
};
```

### Helm Chart Format

```nix
chart = kubenix.lib.helm.fetch {
  repo = "https://charts.example.com";
  chart = "myapp";
  version = "1.2.3";
  sha256 = "sha256-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
};
```

### How to Get Image Digests

1. Use `crane` or `skopeo` to get the digest:
   ```bash
   crane digest ghcr.io/linkwarden/linkwarden:v2.13.5
   ```

2. Or use `nix-prefetch-url` for Helm charts:
   ```bash
   nix-prefetch-url --unpack "https://charts.example.com/myapp-1.2.3.tgz"
   ```

3. Or query the registry API:
   ```bash
   curl -s "https://ghcr.io/v2/linkwarden/linkwarden/manifests/v2.13.5" | jq '.digest'
   ```

### Version Update Checklist

When updating a service to a newer version:

1. [ ] Update Helm chart version in `kubenix.lib.helm.fetch`
2. [ ] Calculate new chart sha256 using `nix-prefetch-url --unpack`
3. [ ] Update container image tag with version
4. [ ] Find and update container image digest (sha256)
5. [ ] Check for breaking changes in release notes
6. [ ] Test the changes locally if possible
7. [ ] Commit and push changes to trigger Flux deployment

## PRE-COMMIT HOOKS: GITLEAKS & SOPS

This repository has **automated security checks** that run before every commit via `.git/hooks/pre-commit`:

### Gitleaks Secret Scanning

**Location:** `.git/hooks/pre-commit`

**What it does:**
- Scans all staged files for potential secrets (API keys, passwords, tokens, etc.)
- Uses gitleaks to detect sensitive data in your changes
- Blocks the commit if secrets are detected

**If gitleaks fails:**
```bash
# Review the gitleaks output
# Remove or redact the secrets from your staged files
# Alternatively, use encrypted files for sensitive data
```

### SOPS Encryption Validation

**What it does:**
- Checks that all `.enc.yaml` and `.enc.yml` files are properly encrypted with SOPS
- Validates the `sops.mac` field exists in encrypted files

**If SOPS validation fails:**
```bash
# Encrypt files with the manifest pipeline
make manifests
# This will run: gmanifests → vmanifests → emanifests (encryption)
```

### Best Practices

1. **Use `make manifests`** before committing - this runs the full pipeline and ensures all secrets are encrypted
2. **Never hardcode secrets** - Use `kubenix.lib.secretsFor` to reference encrypted secrets
3. **Review gitleaks output** - False positives can happen, but always verify before ignoring
4. **Use `.gitleaksignore`** if you have false positives that need to be allowed

## DISABLING MODULES

Prefix with `_` to exclude from rendering:
- `_docling.nix` → not rendered
- `docling.nix` → rendered

## COMMON PATTERNS

### Helm Release

```nix
kubernetes.helm.releases.myapp = {
  chart = kubenix.lib.helm.fetch { repo = "..."; chart = "..."; version = "..."; sha256 = "..."; };
  namespace = homelab.kubernetes.namespaces.applications;
  values = { ... };
};
```

### Raw K8s Resource

```nix
kubernetes.resources.deployments.myapp = {
  metadata.namespace = namespace;
  spec = { ... };
};
```

### Secret Reference

```nix
existingSecret = secretName;  # Reference .enc.nix companion file
```

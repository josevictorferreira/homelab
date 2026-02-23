# SECRETS KNOWLEDGE BASE

> **NEVER hardcode secrets. Always use SOPS encryption with `kubenix.lib.secretsFor`.**

## OVERVIEW

SOPS-encrypted secrets for Kubernetes (vals-injected) and NixOS hosts (sops-nix).

## STRUCTURE

```
secrets/
├── k8s-secrets.enc.yaml      # Kubernetes secrets (vals-injected)
├── hosts-secrets.enc.yaml    # NixOS host secrets (sops-nix)
└── .sops.yaml                # SOPS configuration with age keys
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add K8s secret | `secrets/k8s-secrets.enc.yaml` | Referenced via `kubenix.lib.secretsFor "key"` |
| Add host secret | `secrets/hosts-secrets.enc.yaml` | Used by sops-nix for NixOS |
| Edit secrets | `make secrets` | Interactive fzf selection |
| SOPS config | `.sops.yaml` | Age recipients and path rules |
| K8s secret injection | `modules/kubenix/_lib/default.nix` | `secretsFor` / `secretsInlineFor` helpers |

## CONVENTIONS

### Secret Naming

- Use `snake_case` for all secret keys
- Group related secrets with prefixes: `minio_*`, `postgresql_*`, `vpn_*`

### K8s Secrets (vals injection)

```nix
# In *-config.enc.nix files
"ENV_VAR" = kubenix.lib.secretsFor "secret_key_name";
```

- Use `secretsFor` for standalone values
- Use `secretsInlineFor` (with `+` suffix) when embedding in strings/URLs

### NixOS Secrets (sops-nix)

```nix
# In modules/common/sops.nix
sops.secrets."secret_name" = {
  sopsFile = ../../secrets/hosts-secrets.enc.yaml;
  key = "secret_key_name";
};
```

## ANTI-PATTERNS
  
  | Forbidden | Why |
  |-----------|-----|
  | Hardcode secrets in Nix files | Commits plaintext to git |
  | Use `sops -d > plain && edit && sops -e` | Corrupts encryption metadata |
  | Manual decrypt/re-encrypt | Use `sops --set` for atomic updates |
  | Placeholder values like "REPLACE_ME" | Bypasses vals injection |
  | Commit unencrypted `.enc.yaml` | Must be encrypted before commit |
  
  ## WORKFLOW
  
  1. Add secret to `secrets/k8s-secrets.enc.yaml` via `sops --set`
  2. Reference in kubenix: `kubenix.lib.secretsFor "key_name"`
  3. Verify: `sops -d secrets/k8s-secrets.enc.yaml | grep key_name`
  4. Run `make manifests` to inject and encrypt

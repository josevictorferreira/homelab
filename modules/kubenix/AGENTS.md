# KUBENIX INFRASTRUCTURE

Nix-to-Kubernetes manifest generator. All `.nix` files (except `_*` and `default.nix`) compile to YAML in `.k8s/`.

## STRUCTURE

```
kubenix/
├── apps/              # Application deployments (see apps/AGENTS.md)
├── storage/           # Rook-Ceph operator, cluster, PVs, SMB exports
├── system/            # Cilium CNI, cert-manager, AMD GPU plugin
├── backup/            # Velero, etcd snapshots, postgres restore drills
├── monitoring/        # Prometheus/Grafana stack, backup alerts
├── bootstrap/         # Namespaces, init manifests
├── _lib/              # Helper functions (secretsFor, ingressFor, etc.)
├── _submodules/       # Reusable release template (bjw-s app-template)
├── _base.nix          # Shared kubenix module imports
└── default.nix        # File discovery + renderer
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Add new app | `apps/<app>.nix` + `apps/<app>-config.enc.nix` |
| Storage config | `storage/rook-ceph-{operator,cluster}.nix` |
| Network/CNI | `system/cilium.nix` |
| Secrets helpers | `_lib/default.nix` |
| Reusable template | `_submodules/release.nix` (bjw-s app-template v4) |
| Backup jobs | `backup/velero.nix`, `backup/postgres-restore-drill.nix` |

## CONVENTIONS

- **Discovery**: `default.nix` recursively finds all `.nix` files; prefix with `_` to exclude
- **Secrets**: Use `kubenix.lib.secretsFor "key"` for vals injection; companion files use `.enc.nix` suffix
- **Ingress**: `ingressClassName = "cilium"`, cert-manager cloudflare-issuer
- **TLS**: `secretName = "wildcard-tls"` (cluster-wide wildcard cert)
- **Storage**: `rook-ceph-block` for PVCs, `rook-ceph-objectstore` for S3
- **Images**: Always pin `tag = "v1.0.0@sha256:..."` with digest

## ANTI-PATTERNS

| Forbidden | Why |
|-----------|-----|
| Edit `.k8s/*.yaml` directly | Overwritten by `make manifests` |
| Hardcode secrets in `.nix` | Use `kubenix.lib.secretsFor` |
| Remove `_` prefix without `git add` | New files invisible to Nix flake evaluation |
| Use `with lib;` | Explicit scoping only (see `.docs/rules.md`) |
| Omit image digest | Unreproducible builds; pin `@sha256:...` |

## WORKFLOW

```bash
make manifests   # Full pipeline: generate → inject secrets → encrypt → lock
```

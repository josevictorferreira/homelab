# KUBENIX MODULE

Generates K8s manifests from Nix. All `.nix` files (except `_*` and `default.nix`) become YAML in `.k8s/`.

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

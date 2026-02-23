# KUBENIX APPS

51 application definitions. Each `.nix` file → one YAML manifest in `.k8s/apps/`.

## FILE PATTERNS

| Pattern | Purpose |
|---------|---------|
| `app.nix` | Main application definition |
| `app-config.enc.nix` | Secrets (vals-injected, SOPS-encrypted) |
| `_app.nix` | Disabled/WIP (not rendered) |

## TEMPLATE: New Helm App

```nix
{ kubenix, homelab, ... }:

let
  app = "myapp";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.helm.releases.${app} = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://charts.example.com";
      chart = "myapp";
      version = "1.0.0";
      sha256 = "sha256-XXXX";  # nix-prefetch-url --unpack
    };
    namespace = namespace;
    includeCRDs = true;

    values = {
      image.tag = "1.0.0@sha256:...";  # Pin with digest

      ingress = kubenix.lib.ingressFor app;
      # OR for simpler:
      # ingress = kubenix.lib.ingressDomainFor app;

      persistence = {
        enabled = true;
        storageClass = "rook-ceph-block";
        size = "8Gi";
        annotations."helm.sh/resource-policy" = "keep";
      };

      # External services
      postgresql.enabled = false;
      externalPostgresql = {
        host = "postgresql-18-hl";
        existingSecret = secretName;
      };
    };
  };
}
```

## TEMPLATE: Companion Secret

File: `myapp-config.enc.nix`

```nix
{ kubenix, homelab, ... }:

let
  app = "myapp";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata.namespace = namespace;
    stringData = {
      DB_PASSWORD = kubenix.lib.secretsFor "myapp_db_password";
      API_KEY = kubenix.lib.secretsFor "myapp_api_key";
    };
  };
}
```

## GPU WORKLOADS (AMD)

```nix
nodeSelector."node.kubernetes.io/amd-gpu" = "true";
tolerations = [{ key = "amd-gpu"; operator = "Exists"; effect = "NoSchedule"; }];
resources.limits."amd.com/gpu" = 1;
```

## SHARED STORAGE

For apps needing shared CephFS:
```nix
# Reference existing PVC from storage/shared-storage-pvc.nix
volumes = [{ name = "shared"; persistentVolumeClaim.claimName = "shared-storage"; }];
```

## CHECKLIST: Adding New App

1. Create `apps/myapp.nix` with Helm release or raw resources
2. Create `apps/myapp-config.enc.nix` if secrets needed
3. Add secrets to `secrets/k8s-secrets.enc.yaml` via `make secrets`
4. Run `make manifests`
5. Commit and push → Flux deploys

{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."ghcr-registry-secret" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          ".dockerconfigjson" = kubenix.lib.secretsFor "ghcr_registry_secret";
        };
      };
    };
  };
}

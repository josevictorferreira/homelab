{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes = {
    resources = {
      secrets."ghcr-registry-secret" = {
        metadata = {
          inherit namespace;
        };
        type = "kubernetes.io/dockerconfigjson";
        data = {
          ".dockerconfigjson" = kubenix.lib.secretsFor "ghcr_registry_secret";
        };
      };
    };
  };
}

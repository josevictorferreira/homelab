{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."ghcr-registry-secret" = {
        metadata = {
          inherit namespace;
        };
        type = "kubernetes.io/dockerconfigjson";
        stringData = {
          ".dockerconfigjson" = kubenix.lib.secretsFor "ghcr_registry_secret";
        };
      };
    };
  };
}

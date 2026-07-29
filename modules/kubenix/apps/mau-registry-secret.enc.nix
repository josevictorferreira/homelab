{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."mau-registry-secret" = {
        metadata = {
          inherit namespace;
        };
        type = "kubernetes.io/dockerconfigjson";
        data = {
          ".dockerconfigjson" = kubenix.lib.secretsInlineFor "mau_registry_secret";
        };
      };
    };
  };
}

{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."prowlarr-custom-definitions" = {
        type = "Opaque";
        metadata = {
          inherit namespace;
        };
        data = {
          "custom-indexer" = kubenix.lib.secretsFor "prowlarr_custom_indexer";
        };
      };
    };
  };
}

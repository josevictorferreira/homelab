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
          namespace = namespace;
        };
        data = {
          "custom-indexer" = kubenix.lib.secretsFor "prowlarr_custom_indexer";
        };
      };
    };
  };
}

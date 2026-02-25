{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."ntfy-secrets" = {
        type = "Opaque";
        metadata = {
          inherit namespace;
        };
        stringData = {
          "publicKey" = kubenix.lib.secretsFor "vapid_public_key";
          "privateKey" = kubenix.lib.secretsFor "vapid_private_key";
        };
      };
    };
  };
}

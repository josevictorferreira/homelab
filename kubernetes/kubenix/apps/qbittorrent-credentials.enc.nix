{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."qbittorrent-credentials" = {
        metadata = {
          name = "qbittorrent-credentials";
          namespace = namespace;
        };
        data = {
          "QBT_USERNAME" = kubenix.lib.secretsFor "qbt_username";
          "QBT_PASSWORD" = kubenix.lib.secretsFor "qbt_password";
        };
      };
    };
  };
}

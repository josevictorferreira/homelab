{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."gluetun-vpn-credentials" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          "VPN_SERVICE_PROVIDER" = kubenix.lib.secretsFor "vpn_service_provider";
          "VPN_TYPE" = kubenix.lib.secretsFor "vpn_type";
          "SERVER_COUNTRIES" = kubenix.lib.secretsFor "vpn_server_countries";
          "WIREGUARD_PRIVATE_KEY" = kubenix.lib.secretsFor "vpn_wireguard_private_key";
        };
      };
    };
  };
}

{ kubenix, homelab, ... }:

let
  inherit (homelab.kubernetes.namespaces) certificate;
in
{
  kubernetes = {
    resources = {
      secrets."cloudflare-api-token" = {
        type = "Opaque";
        metadata = {
          namespace = certificate;
        };
        data = {
          "cloudflare-api-token" = kubenix.lib.secretsFor "cloudflare_api_token";
        };
      };
    };
  };
}

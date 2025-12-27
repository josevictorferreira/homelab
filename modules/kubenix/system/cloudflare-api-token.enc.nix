{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.certificate;
in
{
  kubernetes = {
    resources = {
      secrets."cloudflare-api-token" = {
        type = "Opaque";
        metadata = {
          namespace = namespace;
        };
        data = {
          "cloudflare-api-token" = kubenix.lib.secretsFor "cloudflare_api_token";
        };
      };
    };
  };
}

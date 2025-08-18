{ clusterLib, ... }:

let
  namespace = "cert-manager";
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
          "cloudflare-api-token" = clusterLib.secretsFor "cloudflare_api_token";
        };
      };
    };
  };
}

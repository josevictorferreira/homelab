{ secretsFor, ... }:

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
          "cloudflare-api-token" = secretsFor "cloudflare-api-token";
        };
      };
    };
  };
}

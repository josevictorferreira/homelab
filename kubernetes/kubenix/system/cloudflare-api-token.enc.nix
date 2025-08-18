{ k8sLib, ... }:

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
          "cloudflare-api-token" = k8sLib.secretsFor "cloudflare_api_token";
        };
      };
    };
  };
}

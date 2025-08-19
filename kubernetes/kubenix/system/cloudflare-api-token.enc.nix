{ kubenix, labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.certificate;
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

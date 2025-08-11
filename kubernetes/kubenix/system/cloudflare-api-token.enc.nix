{ kubenix, secretsFor, ... }:

let
  namespace = "cert-manager";
in
{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

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

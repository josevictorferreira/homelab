{ kubenix, secretsPath, ... }:

let
  namespace = "cert-manager";
in
{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

  sops.secrets."cloudflare-api-token" = {
    file = "${secretsPath}/k8s-secret.enc.yaml";
    key = "cloudflare-api-token";
    type = "string";
  };

  kubernetes = {
    resources."secrets.cloudflare-api-token" = {
      metadata = {
        name = "cloudflare-api-token";
        namespace = namespace;
      };
      data = {
        "cloudflare-api-token" = kubenix.lib.sops.getSecret "cloudflare-api-token";
      };
    };
  };
}

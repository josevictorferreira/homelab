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
        # The token is stored base64-encoded in k8s-secrets, and cert-manager
        # sends the value verbatim as a Bearer header. Must stay `data` (not
        # `stringData`) or Cloudflare rejects it with "6111: Invalid format for
        # Authorization header" and every DNS-01 challenge fails to present.
        data = {
          "cloudflare-api-token" = kubenix.lib.secretsFor "cloudflare_api_token";
        };
      };
    };
  };
}

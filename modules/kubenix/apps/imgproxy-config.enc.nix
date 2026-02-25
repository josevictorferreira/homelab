{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."imgproxy-config" = {
        metadata = {
          name = "imgproxy-config";
          inherit namespace;
        };
        data = {
          "IMGPROXY_KEY" = kubenix.lib.secretsFor "imgproxy_key";
          "IMGPROXY_SALT" = kubenix.lib.secretsFor "imgproxy_salt";
        };
      };
    };
  };
}

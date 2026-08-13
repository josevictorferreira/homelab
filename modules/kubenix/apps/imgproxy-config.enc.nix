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
        # These are stored base64-encoded in k8s-secrets, and imgproxy requires
        # the decoded hex. Must stay `data` (not `stringData`) or the container
        # receives the base64 text and exits with "expected to be hex-encoded".
        data = {
          "IMGPROXY_KEY" = kubenix.lib.secretsFor "imgproxy_key";
          "IMGPROXY_SALT" = kubenix.lib.secretsFor "imgproxy_salt";
        };
      };
    };
  };
}

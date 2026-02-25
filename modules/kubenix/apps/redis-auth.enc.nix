{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."redis-auth" = {
        type = "Opaque";
        metadata = {
          inherit namespace;
        };
        stringData = {
          "redis-password" = kubenix.lib.secretsFor "redis_password";
        };
      };
    };
  };
}

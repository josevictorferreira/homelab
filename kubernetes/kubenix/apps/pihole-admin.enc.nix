{ kubenix, labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."pihole-admin" = {
        type = "Opaque";
        metadata = {
          namespace = namespace;
        };
        data = {
          "password" = kubenix.lib.secretsFor "pihole_admin_password";
        };
      };
    };
  };
}

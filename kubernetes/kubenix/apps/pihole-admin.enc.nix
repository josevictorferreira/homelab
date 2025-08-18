{ k8sLib, ... }:

let
  namespace = "apps";
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
          "password" = k8sLib.secretsFor "pihole_admin_password";
        };
      };
    };
  };
}

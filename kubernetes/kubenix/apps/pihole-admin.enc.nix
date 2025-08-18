{ clusterLib, ... }:

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
          "password" = clusterLib.secretsFor "pihole_admin_password";
        };
      };
    };
  };
}

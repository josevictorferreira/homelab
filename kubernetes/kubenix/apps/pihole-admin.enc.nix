{ secretsFor, ... }:

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
          "password" = secretsFor "pihole-admin-password";
        };
      };
    };
  };
}

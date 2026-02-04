{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."keycloak-env" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "DB_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
          "KEYCLOAK_ADMIN_PASSWORD" = kubenix.lib.secretsFor "keycloak_admin_password";
        };
      };
    };
  };
}

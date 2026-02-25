{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."keycloak-env" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "db-username" = "postgres";
          "db-password" = kubenix.lib.secretsFor "postgresql_admin_password";
          "KEYCLOAK_ADMIN_PASSWORD" = kubenix.lib.secretsFor "keycloak_admin_password";
        };
      };
    };
  };
}

{ clusterLib, ... }:

let
  namespace = "monitoring";
in
{
  kubernetes = {
    resources = {
      secrets."grafana-admin" = {
        type = "Opaque";
        metadata = {
          namespace = namespace;
        };
        data = {
          "ADMIN_USER" = clusterLib.secretsFor "grafana_admin_username";
          "ADMIN_PASSWORD" = clusterLib.secretsFor "grafana_admin_password";
        };
      };
    };
  };
}

{ k8sLib, ... }:

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
          "ADMIN_USER" = k8sLib.secretsFor "grafana_admin_username";
          "ADMIN_PASSWORD" = k8sLib.secretsFor "grafana_admin_password";
        };
      };
    };
  };
}

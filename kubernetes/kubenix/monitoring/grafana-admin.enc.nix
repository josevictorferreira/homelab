{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
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
          "ADMIN_USER" = kubenix.lib.secretsFor "grafana_admin_username";
          "ADMIN_PASSWORD" = kubenix.lib.secretsFor "grafana_admin_password";
        };
      };
    };
  };
}

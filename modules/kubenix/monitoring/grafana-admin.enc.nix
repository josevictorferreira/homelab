{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  contactPoints = {
    apiVersion = 1;
    contactPoints = [
      {
        orgId = 1;
        name = "Ntfy";
        receivers = [
          {
            uid = "dezclgug3tb0ga";
            type = "webhook";
            settings = {
              headers = {
                "X-Template" = "grafana";
              };
              httpMethod = "POST";
              url = "http://ntfy.apps.svc.cluster.local/homelab";
            };
            disableResolveMessage = false;
          }
        ];
      }
      {
        orgId = 1;
        name = "Matrix";
        receivers = [
          {
            uid = "matrix-alerts";
            type = "webhook";
            settings = {
              httpMethod = "POST";
              url = "http://homelab-bridge.apps.svc.cluster.local:8080/webhooks/grafana";
            };
            disableResolveMessage = false;
          }
        ];
      }
    ];
  };
in
{
  kubernetes = {
    resources = {
      secrets."grafana-admin" = {
        type = "Opaque";
        metadata = {
          inherit namespace;
        };
        data = {
          "ADMIN_USER" = kubenix.lib.secretsFor "grafana_admin_username";
          "ADMIN_PASSWORD" = kubenix.lib.secretsFor "grafana_admin_password";
        };
        stringData = {
          "GF_DATABASE_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
          "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET" = kubenix.lib.secretsFor "grafana_oidc_client_secret";
        };
      };

      configMaps."grafana-alerting-contactpoints" = {
        metadata = {
          inherit namespace;
          labels = {
            grafana_alert = "1";
          };
        };
        data."contactpoints.yaml" = kubenix.lib.toYamlStr contactPoints;
      };
    };
  };
}

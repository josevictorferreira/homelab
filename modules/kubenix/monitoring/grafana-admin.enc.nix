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
            type = "matrix";
            settings = {
              homeserverAddress = "http://tuwunel.apps.svc.cluster.local:8008";
              homeserverUseTLS = false;
              roomId = "!d0dYdkGOcX7cchTc4H:josevictor.me";
              userId = "@homelab-bridge:josevictor.me";
              password = kubenix.lib.secretsFor "homelab_bridge_matrix_password";
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

{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  ntfyContactPoint = {
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
    ];
  };
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

      configMaps."grafana-alerting-contactpoints" = {
        metadata = {
          namespace = namespace;
          labels = {
            grafana_alert = "1";
          };
        };
        data."contact-points.yaml" = kubenix.lib.toYamlStr ntfyContactPoint;
      };
    };
  };
}

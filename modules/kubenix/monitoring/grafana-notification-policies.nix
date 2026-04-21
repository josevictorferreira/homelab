{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  notificationPolicy = {
    apiVersion = 1;
    policies = [
      {
        orgId = 1;
        receiver = "Matrix";
        "group_by" = [
          "alertname"
          "namespace"
          "severity"
        ];
        "group_wait" = "30s";
        "group_interval" = "5m";
        "repeat_interval" = "4h";
        routes = [
          {
            receiver = "Matrix";
            matchers = [ ];
            continue = false;
          }
        ];
      }
    ];
  };
in
{
  kubernetes.resources.configMaps."grafana-alerting-notification-policies" = {
    metadata = {
      inherit namespace;
      labels = {
        grafana_alerting_notifications = "true";
      };
    };
    data."notification-policies.yaml" = kubenix.lib.toYamlStr notificationPolicy;
  };
}

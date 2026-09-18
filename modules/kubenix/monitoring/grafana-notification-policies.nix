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
      # Must be `grafana_alert` — that is the label the grafana-sc-alerts
      # sidecar watches (LABEL=grafana_alert), and it is what the contactpoints
      # and rule ConfigMaps already use. With any other label the sidecar never
      # picks this up, Grafana silently falls back to its built-in default
      # policy, and every alert routes to `grafana-default-email` -> "SMTP not
      # configured" -> no alert is ever delivered.
      labels = {
        grafana_alert = "1";
      };
    };
    data."notification-policies.yaml" = kubenix.lib.toYamlStr notificationPolicy;
  };
}

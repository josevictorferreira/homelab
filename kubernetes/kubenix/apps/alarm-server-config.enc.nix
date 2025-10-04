{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."alarm-server-config" = {
        metadata = {
          namespace = namespace;
        };
        type = "Opaque";
        stringData = {
          MQTT_URL = "mqtt://josevictor:${kubenix.lib.secretsInlineFor "rabbitmq_password"}@rabbitmq-headless:1883";
          MQTT_TOPIC = "alarms";
          MESSAGE_PARSER = "icsee";
          MESSAGE_FILTERS = "alarm,log";
          MESSAGE_PRIORITY = "low";
          LOG_LEVEL = "info";
          LOG_OUTPUT = "stdout";
          NTFY_ENABLED = "true";
          NTFY_URL = kubenix.lib.domainFor "ntfy";
          NTFY_TOPIC = "camera";
        };
      };
    };
  };
}

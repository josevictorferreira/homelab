{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
in

{
  kubernetes.objects = [
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "velero-dashboard";
        inherit namespace;
        labels = {
          grafana_dashboard = "1";
          "app.kubernetes.io/part-of" = "backup-observability";
        };
      };
      data."velero-dashboard.json" = builtins.readFile ./dashboards/velero.json;
    }
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "minio-dashboard";
        inherit namespace;
        labels = {
          grafana_dashboard = "1";
          "app.kubernetes.io/part-of" = "backup-observability";
        };
      };
      data."minio-dashboard.json" = builtins.readFile ./dashboards/minio.json;
    }
  ];
}

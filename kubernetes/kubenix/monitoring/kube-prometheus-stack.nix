{ kubenix, clusterLib, ... }:

let
  namespace = "monitoring";
in
{
  kubernetes = {
    helm.releases."kube-prometheus-stack" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "oci://ghcr.io/prometheus-community/charts";
          chart = "kube-prometheus-stack";
          version = "76.4.0";
          sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
        };
      includeCRDs = true;
      namespace = namespace;
      noHooks = true;
      values = {
        crds.enabled = true;
        grafana = {
          enabled = true;
          persistence = {
            enabled = true;
            type = "pvc";
            storageClassName = "rook-ceph-block";
            accessModes = [ "ReadWriteOnce" ];
            size = "10Gi";
            finalizers = [ "kubernetes.io/pvc-protection" ];
          };
          service = clusterLib.plainServiceFor "grafana";
          serviceMonitor.enabled = true;
          admin = {
            existingSecret = "grafana-admin";
            userKey = "ADMIN_USER";
            passwordKey = "ADMIN_PASSWORD";
          };
          ingress = clusterLib.ingressDomainFor "grafana";
        };
        prometheus = {
          enabled = true;
          prometheusSpec = {
            replicas = 1;
            podMonitorSelectorNilUsesHelmValues = false;
            serviceMonitorSelectorNilUsesHelmValues = false;
            retention = "15d";
            storageSpec = {
              volumeClaimTemplate = {
                spec = {
                  storageClassName = "rook-ceph-block";
                  accessModes = [ "ReadWriteOnce" ];
                  resources.request.storage = "25Gi";
                };
              };
            };
          };
        };
      };
    };
  };
}

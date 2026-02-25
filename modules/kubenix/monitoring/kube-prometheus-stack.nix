{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
in
{
  kubernetes = {
    helm.releases."kube-prometheus-stack" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://prometheus-community.github.io/helm-charts";
          chart = "kube-prometheus-stack";
          version = "77.11.1";
          sha256 = "sha256-q56T7iEqKm60iEhgeuLVhEKhaDpR8DebjW8+/gphN5Q=";
        };
      includeCRDs = true;
      inherit namespace;
      noHooks = true;
      values = {
        namespaceOverride = namespace;
        crds.enabled = true;
        kubeProxy.enabled = false;
        grafana = {
          enabled = true;
          sidecar = {
            dashboards.enabled = true;
            datasources.enabled = true;
            alerts.enabled = true;
          };
          inherit namespace;
          persistence = {
            enabled = true;
            type = "pvc";
            storageClassName = "rook-ceph-block";
            accessModes = [ "ReadWriteOnce" ];
            size = "10Gi";
            finalizers = [ "kubernetes.io/pvc-protection" ];
          };
          service = kubenix.lib.plainServiceFor "grafana";
          serviceMonitor.enabled = true;
          admin = {
            existingSecret = "grafana-admin";
            userKey = "ADMIN_USER";
            passwordKey = "ADMIN_PASSWORD";
          };
          ingress = kubenix.lib.ingressDomainFor "grafana";
        };
        prometheusOperator = {
          enabled = true;
          tls.enabled = false;
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
                  resources.requests.storage = "25Gi";
                };
              };
            };
          };
        };
      };
    };
    resources = {
      services = {
        "kube-prometheus-stack-coredns" = { metadata.namespace = lib.mkForce "kube-system"; };
        "kube-prometheus-stack-kube-etcd" = { metadata.namespace = lib.mkForce "kube-system"; };
        "kube-prometheus-stack-kube-scheduler" = { metadata.namespace = lib.mkForce "kube-system"; };
        "kube-prometheus-stack-kube-controller-manager" = { metadata.namespace = lib.mkForce "kube-system"; };
      };
    };
  };
}

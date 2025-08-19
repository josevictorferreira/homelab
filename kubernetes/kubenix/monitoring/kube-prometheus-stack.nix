{ lib, kubenix, labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.monitoring;
in
{
  kubernetes = {
    helm.releases."kube-prometheus-stack" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://prometheus-community.github.io/helm-charts";
          chart = "kube-prometheus-stack";
          version = "76.4.0";
          sha256 = "sha256-8I29zkZDYOAJ5eodRbl52KA6SdilVsaLWIDDCRZPe7I=";
        };
      includeCRDs = true;
      namespace = namespace;
      noHooks = true;
      values = {
        namespaceOverride = namespace;
        crds.enabled = true;
        kubeProxy.enabled = false;
        grafana = {
          enabled = true;
          namespace = namespace;
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
      services."kube-prometheus-stack-coredns" = {
        metadata = {
          namespace = lib.mkForce "kube-system";
        };
      };
      services."kube-prometheus-stack-kube-etcd" = {
        metadata = {
          namespace = lib.mkForce "kube-system";
        };
      };
      services."kube-prometheus-stack-kube-scheduler" = {
        metadata = {
          namespace = lib.mkForce "kube-system";
        };
      };
      services."kube-prometheus-stack-kube-controller-manager" = {
        metadata = {
          namespace = lib.mkForce "kube-system";
        };
      };
    };
  };
}

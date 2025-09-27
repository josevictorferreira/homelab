{ lib, kubenix, homelab, ... }:

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
          sidecar.dashboards.enabled = true;
          sidecar.datasources.enabled = true;
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
          alerting = {
            "contactpoints.yaml" = ntfyContactPoint;
          };
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

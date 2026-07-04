{
  lib,
  kubenix,
  homelab,
  ...
}:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  keycloakOidc = "https://identity.${homelab.domain}/realms/homelab/protocol/openid-connect";
in
{
  kubernetes = {
    helm.releases."kube-prometheus-stack" = {
      chart = kubenix.lib.helm.fetch {
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
            dashboards = {
              enabled = true;
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "100m";
                  memory = "128Mi";
                };
              };
            };
            datasources = {
              enabled = true;
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "100m";
                  memory = "128Mi";
                };
              };
            };
            alerts = {
              enabled = true;
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "100m";
                  memory = "128Mi";
                };
              };
            };
          };
          inherit namespace;
          persistence.enabled = false;
          service = kubenix.lib.plainServiceFor "grafana";
          serviceMonitor.enabled = true;
          resources = {
            requests = {
              cpu = "100m";
              memory = "256Mi";
            };
            limits = {
              cpu = "500m";
              memory = "512Mi";
            };
          };
          admin = {
            existingSecret = "grafana-admin";
            userKey = "ADMIN_USER";
            passwordKey = "ADMIN_PASSWORD";
          };
          ingress = kubenix.lib.ingressDomainFor "grafana";
          affinity = homelab.kubernetes.affinities.piNode;
          tolerations = [
            {
              key = "pi-only";
              operator = "Equal";
              value = "true";
              effect = "NoSchedule";
            }
          ];
          "grafana.ini".database = {
            type = "postgres";
            host = "postgresql-18-hl.apps.svc.cluster.local:5432";
            name = "grafana";
            user = "postgres";
            password = "$__env{GF_DATABASE_PASSWORD}";
          };
          envValueFrom.GF_DATABASE_PASSWORD.secretKeyRef = {
            name = "grafana-admin";
            key = "GF_DATABASE_PASSWORD";
          };
          "grafana.ini"."auth.generic_oauth" = {
            enabled = true;
            name = "Keycloak";
            allow_sign_up = true;
            client_id = "grafana";
            client_secret = "$__env{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}";
            scopes = "openid profile email";
            auth_url = "${keycloakOidc}/auth";
            token_url = "${keycloakOidc}/token";
            api_url = "${keycloakOidc}/userinfo";
            role_attribute_path = "contains(realm_access.roles[*], 'grafana-admin') && 'Admin' || 'Viewer'";
            oauth_auto_login = true;
          };
          envValueFrom.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET.secretKeyRef = {
            name = "grafana-admin";
            key = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET";
          };
        };
        prometheusOperator = {
          enabled = true;
          tls.enabled = false;
          resources = {
            requests = {
              cpu = "100m";
              memory = "128Mi";
            };
            limits = {
              cpu = "200m";
              memory = "256Mi";
            };
          };
        };
        alertmanager = {
          enabled = true;
          alertmanagerSpec = {
            resources = {
              requests = {
                cpu = "100m";
                memory = "256Mi";
              };
              limits = {
                cpu = "500m";
                memory = "512Mi";
              };
            };
          };
        };
        prometheus = {
          enabled = true;
          prometheusSpec = {
            replicas = 1;
            podMonitorSelectorNilUsesHelmValues = false;
            serviceMonitorSelectorNilUsesHelmValues = false;
            retention = "15d";
            retentionSize = "40GiB";
            resources = {
              requests = {
                cpu = "1";
                memory = "2Gi";
              };
              limits = {
                cpu = "2";
                memory = "4Gi";
              };
            };
            storageSpec = {
              volumeClaimTemplate = {
                spec = {
                  storageClassName = kubenix.lib.defaultStorageClass;
                  accessModes = [ "ReadWriteOnce" ];
                  resources.requests.storage = "50Gi";
                };
              };
            };
            affinity.nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "NotIn";
                      values = [
                        "lab-delta-cp"
                        "lab-alpha-cp"
                      ];
                    }
                  ];
                }
              ];
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = [ "lab-beta-cp" ];
                    }
                  ];
                }
              ];
            };
          };
        };
      };
    };
    resources = {
      services = {
        "kube-prometheus-stack-coredns" = {
          metadata.namespace = lib.mkForce "kube-system";
        };
        "kube-prometheus-stack-kube-etcd" = {
          metadata.namespace = lib.mkForce "kube-system";
        };
        "kube-prometheus-stack-kube-scheduler" = {
          metadata.namespace = lib.mkForce "kube-system";
        };
        "kube-prometheus-stack-kube-controller-manager" = {
          metadata.namespace = lib.mkForce "kube-system";
        };
      };
    };
  };
}

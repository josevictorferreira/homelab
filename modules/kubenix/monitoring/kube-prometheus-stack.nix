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
        version = "92.16.1";
        sha256 = "sha256-HHR7pqy9HMVtiMNexn1zVmlggpcRBrCURThChCFO3dI=";
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
              # The provisioning dir is an emptyDir, so without an init
              # container the plain sidecar writes the alerting YAML *after*
              # grafana has already read provisioning at startup. Grafana then
              # never picks it up, and the sidecar's hot-reload call to
              # /api/admin/provisioning/alerting/reload 401s because the local
              # admin password in the postgres DB no longer matches the secret.
              # Net effect: alerting provisioning never applied at all.
              initAlerts = true;
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
          "grafana.ini".server.root_url = "https://grafana.${homelab.domain}";
          # Grafana 13 starts every bundled backend plugin at boot. Only
          # Prometheus, Alertmanager and Loki are used as datasources.
          "grafana.ini".plugins.disable_plugins = lib.concatStringsSep "," [
            "cloudwatch"
            "elasticsearch"
            "grafana-azure-monitor-datasource"
            "grafana-postgresql-datasource"
            "grafana-pyroscope-datasource"
            "grafana-testdata-datasource"
            "graphite"
            "influxdb"
            "jaeger"
            "mssql"
            "mysql"
            "opentsdb"
            "parca"
            "stackdriver"
            "tempo"
            "zipkin"
          ];
          "grafana.ini".database = {
            type = "postgres";
            host = "${kubenix.lib.postgresHost}:5432";
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
            # 2026-10-21: 40GiB left no headroom for the WAL on the 50Gi volume
            # (ENOSPC crash loop) while Ceph itself was full.
            retention = "7d";
            retentionSize = "20GiB";
            # 2026-10-06: WAL replay on Ceph outlasted the operator's default
            # 15 min startup probe, so the pod was killed mid-replay (exit 137)
            # in a loop and the WAL never got compacted. Allow one hour.
            maximumStartupDurationSeconds = 3600;
            resources = {
              requests = {
                cpu = "300m";
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

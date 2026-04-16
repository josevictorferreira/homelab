{ kubenix, homelab, ... }:

let
  name = "tuwunel";
  dataPvcName = "${name}-data-v2";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources = {

    persistentVolumeClaims.${dataPvcName} = {
      metadata = {
        name = dataPvcName;
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = kubenix.lib.defaultStorageClass;
        resources.requests.storage = "10Gi";
      };
    };

    deployments.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            terminationGracePeriodSeconds = 120;
            containers = [
              {
                inherit name;
                image = "ghcr.io/matrix-construct/tuwunel:v1.5.1@sha256:25693407bc059eec7e161418edd02b2b7c010516c855056a7672883b04f71b11";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  {
                    name = "http";
                    containerPort = 8008;
                    protocol = "TCP";
                  }
                ];
                env = [
                  {
                    name = "TUWUNEL_CONFIG";
                    value = "/etc/tuwunel/tuwunel.toml";
                  }
                  {
                    name = "TUWUNEL_SERVER_NAME";
                    value = "josevictor.me";
                  }
                  {
                    name = "TUWUNEL_DATABASE_PATH";
                    value = "/var/lib/tuwunel";
                  }
                  {
                    name = "TUWUNEL_ADDRESS";
                    value = "0.0.0.0";
                  }
                  {
                    name = "TUWUNEL_PORT";
                    value = "8008";
                  }
                  {
                    name = "TUWUNEL_ALLOW_FEDERATION";
                    value = "false";
                  }
                  {
                    name = "TUWUNEL_ALLOW_REGISTRATION";
                    value = "true";
                  }
                  {
                    name = "TUWUNEL_REGISTRATION_TOKEN";
                    valueFrom.secretKeyRef = {
                      name = "${name}-env";
                      key = "registration_token";
                    };
                  }
                  {
                    name = "TUWUNEL_WELL_KNOWN__CLIENT";
                    value = "https://matrix.josevictor.me";
                  }
                  {
                    name = "TUWUNEL_WELL_KNOWN__SERVER";
                    value = "matrix.josevictor.me:443";
                  }
                  {
                    name = "TUWUNEL_EMERGENCY_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "${name}-env";
                      key = "TUWUNEL_EMERGENCY_PASSWORD";
                    };
                  }
                  {
                    name = "TUWUNEL_DB_POOL_AFFINITY";
                    value = "false";
                  }
                  {
                    name = "TUWUNEL_DB_POOL_WORKERS";
                    value = "16";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                startupProbe = {
                  httpGet = {
                    path = "/_matrix/client/versions";
                    port = 8008;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  failureThreshold = 30;
                  timeoutSeconds = 30;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/_matrix/client/versions";
                    port = 8008;
                  };
                  initialDelaySeconds = 600;
                  periodSeconds = 30;
                  failureThreshold = 5;
                  timeoutSeconds = 30;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/_matrix/client/versions";
                    port = 8008;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  failureThreshold = 10;
                  timeoutSeconds = 30;
                };
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/var/lib/tuwunel";
                  }
                  {
                    name = "config";
                    mountPath = "/etc/tuwunel/tuwunel.toml";
                    subPath = "tuwunel.toml";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = dataPvcName;
              }
              {
                name = "config";
                secret.secretName = "${name}-config";
              }
            ];
          };
        };
      };
    };

    services.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        type = "ClusterIP";
        selector.app = name;
        ports = [
          {
            name = "http";
            port = 8008;
            targetPort = 8008;
          }
        ];
      };
    };

    ingresses.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        ingressClassName = kubenix.lib.defaultIngressClass;
        rules = [
          {
            host = "matrix.josevictor.me";
            http = {
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend = {
                    service = {
                      inherit name;
                      port.number = 8008;
                    };
                  };
                }
              ];
            };
          }
          {
            host = "josevictor.me";
            http = {
              paths = [
                {
                  path = "/.well-known/matrix";
                  pathType = "Prefix";
                  backend = {
                    service = {
                      inherit name;
                      port.number = 8008;
                    };
                  };
                }
              ];
            };
          }
        ];
        tls = [
          {
            hosts = [
              "matrix.josevictor.me"
              "josevictor.me"
            ];
            secretName = kubenix.lib.defaultTLSSecret;
          }
        ];
      };
    };
  };
}

{ homelab, ... }:

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
        storageClassName = "rook-ceph-block";
        resources.requests.storage = "10Gi";
      };
    };

    deployments.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        replicas = 1;
        strategy.type = "RollingUpdate";
        strategy.rollingUpdate = {
          maxUnavailable = 0;
          maxSurge = 1;
        };
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
                    memory = "512Mi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                livenessProbe = {
                  httpGet = {
                    path = "/_matrix/client/versions";
                    port = 8008;
                  };
                  initialDelaySeconds = 90;
                  periodSeconds = 10;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/_matrix/client/versions";
                    port = 8008;
                  };
                  initialDelaySeconds = 150;
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
                configMap.name = name;
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

    configMaps.${name} = {
      metadata = {
        inherit name namespace;
      };
      data = {
        "tuwunel.toml" = ''
          [global]
          server_name = "josevictor.me"
          database_path = "/var/lib/tuwunel"
          address = "0.0.0.0"
          port = 8008
          allow_federation = false
          allow_registration = true
          new_user_displayname_suffix = ""

          allow_legacy_media = true
          url_preview_domain_contains_allowlist = ["*"]
          max_request_size = 52428800

          allow_local_presence = true
          allow_encryption = true

          [global.well_known]
          client = "https://matrix.josevictor.me"
          server = "matrix.josevictor.me:443"
        '';
      };
    };
    ingresses.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        ingressClassName = "cilium";
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
            secretName = "wildcard-tls";
          }
        ];
      };
    };
  };
}

{ homelab, ... }:

let
  name = "tuwunel";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.persistentVolumeClaims."${name}-data" = {
    metadata = {
      name = "${name}-data";
      inherit namespace;
    };
    spec = {
      accessModes = [ "ReadWriteOnce" ];
      storageClassName = "rook-ceph-block";
      resources.requests.storage = "10Gi";
    };
  };

  kubernetes.resources.deployments.${name} = {
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
          terminationGracePeriodSeconds = 60;
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
                  name = "TUWUNEL_SERVER_NAME";
                  value = "matrixx.josevictor.me";
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
                initialDelaySeconds = 30;
                periodSeconds = 10;
              };
              readinessProbe = {
                httpGet = {
                  path = "/_matrix/client/versions";
                  port = 8008;
                };
                initialDelaySeconds = 5;
                periodSeconds = 5;
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
  {
    name = "token";
    mountPath = "/etc/tuwunel/registration_token";
    subPath = "registration_token";
    readOnly = true;
  }
];
            }
          ];
volumes = [
  {
    name = "data";
    persistentVolumeClaim.claimName = "${name}-data";
  }
  {
    name = "config";
    configMap.name = "${name}-config";
  }
  {
    name = "token";
    secret.secretName = "${name}-env";
  }
];
        };
      };
    };
  };

  kubernetes.resources.services.${name} = {
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

  kubernetes.resources.configMaps."${name}-config" = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    data = {
      "tuwunel.toml" = ''
        [global]
        server_name = "matrixx.josevictor.me"
        database_path = "/var/lib/tuwunel"
        address = "0.0.0.0"
        port = 8008
        allow_federation = false
        federate_created_rooms = false
        allow_registration = true
        registration_token_file = "/etc/tuwunel/registration_token"
      '';
    };
  };

  kubernetes.resources.ingresses.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      ingressClassName = "cilium";
      rules = [
        {
          host = "matrixx.josevictor.me";
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = name;
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
          hosts = [ "matrixx.josevictor.me" ];
          secretName = "josevictor-me-wildcard-tls";
        }
      ];
    };
  };
}

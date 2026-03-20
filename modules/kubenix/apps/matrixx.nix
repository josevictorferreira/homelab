{ kubenix, homelab, ... }:

let
  name = "matrixx";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources = {
    deployments.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            containers = [
              {
                inherit name;
                image = "ghcr.io/element-hq/dendrite-monolith:v0.15.2@sha256:e9a93fe88ab6c3716af5a495e021201e9aee30a8509dadb4a7ebd7d859880144";
                command = [
                  "/usr/bin/dendrite"
                  "-config"
                  "/etc/dendrite/dendrite.yaml"
                  "-http-bind-address"
                  ":8008"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8008;
                    protocol = "TCP";
                  }
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/dendrite";
                    readOnly = true;
                  }
                  {
                    name = "media";
                    mountPath = "/data/media";
                  }
                  {
                    name = "key";
                    mountPath = "/var/lib/dendrite";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                secret = {
                  secretName = "matrixx-config";
                };
              }
              {
                name = "media";
                persistentVolumeClaim = {
                  claimName = "matrixx-media";
                };
              }
              {
                name = "key";
                secret = {
                  secretName = "matrixx-config";
                  items = [{
                    key = "matrix_key.pem";
                    path = "matrix_key.pem";
                  }];
                };
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
    persistentVolumeClaims.matrixx-media = {
      metadata = {
        inherit namespace;
        name = "matrixx-media";
      };
      spec = {
        storageClassName = "rook-ceph-block";
        accessModes = [ "ReadWriteOnce" ];
        resources = {
          requests = {
            storage = "5Gi";
          };
        };
      };
    };
    ingresses.${name} = {
      metadata = {
        inherit namespace;
        annotations = {
          "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
        };
      };
      spec = {
        ingressClassName = "cilium";
        rules = [{
          host = "${name}.${homelab.domain}";
          http = {
            paths = [{
              path = "/";
              pathType = "Prefix";
              backend = {
                service = {
                  name = name;
                  port = {
                    name = "http";
                  };
                };
              };
            }];
          };
        }];
        tls = [{
          hosts = [ "${name}.${homelab.domain}" ];
          secretName = "wildcard-tls";
        }];
      };
    };
    jobs.matrixx-create-user = {
      metadata = {
        inherit namespace;
        name = "matrixx-create-user";
      };
      spec = {
        template = {
          spec = {
            restartPolicy = "OnFailure";
            volumes = [
              {
                name = "config";
                secret = {
                  secretName = "matrixx-config";
                };
              }
              {
                name = "key";
                secret = {
                  secretName = "matrixx-config";
                  items = [{
                    key = "matrix_key.pem";
                    path = "matrix_key.pem";
                  }];
                };
              }
            ];
            containers = [{
              name = "create-account";
              image = "ghcr.io/element-hq/dendrite-monolith:v0.15.2@sha256:e9a93fe88ab6c3716af5a495e021201e9aee30a8509dadb4a7ebd7d859880144";
              command = [
                "/bin/sh"
                "-c"
                "echo $PASSWORD | /usr/bin/create-account -config /etc/dendrite/dendrite.yaml -username dendrite-test -passwordstdin -url http://matrixx.apps.svc.cluster.local:8008"
              ];
              env = [{
                name = "PASSWORD";
                valueFrom = {
                  secretKeyRef = {
                    name = "dendrite-test-password";
                    key = "dendrite_test_user_password";
                  };
                };
              }];
              volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/dendrite";
                  readOnly = true;
                }
                {
                  name = "key";
                  mountPath = "/var/lib/dendrite";
                  readOnly = true;
                }
              ];
            }];
          };
        };
        backoffLimit = 4;
      };
    };
  };
}

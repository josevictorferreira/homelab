{ homelab, ... }:

let
  name = "attic";
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "attic";
  image = {
    registry = "ghcr.io";
    repository = "zhaofengli/attic";
    tag = "main@sha256:317924e10e70416e69d401880bb71b3aae69b413ecafcfc54018f61929464526";
  };
  configToml = ''
    listen = "[::]:8080"

    [database]
    heartbeat = true

    [storage]
    type = "s3"
    region = "us-east-1"
    bucket = "${bucketName}"
    endpoint = "https://objectstore.josevictor.me"

    [chunking]
    nar-size-threshold = 65536
    min-size = 16384
    avg-size = 65536
    max-size = 262144

    [compression]
    type = "zstd"
    level = 8

    [garbage-collection]
    interval = "12 hours"
    default-retention-period = "3 months"
  '';
  # Config is mounted via subPath, so ConfigMap edits never propagate to a
  # running pod; stamping the hash on the pod template forces a rollout.
  configHash = builtins.hashString "sha256" configToml;
in
{
  kubernetes.resources.deployments.${name} = {
    metadata = {
      inherit name namespace;
      labels = {
        app = name;
      };
    };
    spec = {
      replicas = 1;
      selector.matchLabels.app = name;
      strategy = {
        type = "Recreate";
      };
      template = {
        metadata.labels.app = name;
        metadata.annotations."attic.josevictor.me/config-hash" = configHash;
        spec = {
          terminationGracePeriodSeconds = 30;
          containers = [
            {
              inherit name;
              image = "${image.registry}/${image.repository}:${image.tag}";
              args = [
                "-f"
                "/etc/attic/config.toml"
              ];
              ports = [
                {
                  name = "http";
                  containerPort = 8080;
                  protocol = "TCP";
                }
              ];
              envFrom = [
                {
                  secretRef.name = "${name}-config";
                }
              ];
              env = [
                {
                  name = "AWS_ACCESS_KEY_ID";
                  valueFrom.secretKeyRef = {
                    name = "${name}-s3";
                    key = "AWS_ACCESS_KEY_ID";
                  };
                }
                {
                  name = "AWS_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "${name}-s3";
                    key = "AWS_SECRET_ACCESS_KEY";
                  };
                }
              ];
              volumeMounts = [
                {
                  name = "config";
                  mountPath = "/etc/attic/config.toml";
                  subPath = "config.toml";
                  readOnly = true;
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "1Gi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
              livenessProbe = {
                tcpSocket = {
                  port = 8080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 20;
              };
              readinessProbe = {
                tcpSocket = {
                  port = 8080;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
            }
          ];
          volumes = [
            {
              name = "config";
              configMap = {
                name = "${name}-config";
              };
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.services.${name} = {
    metadata = {
      inherit name namespace;
      annotations = {
        "lbipam.cilium.io/ips" = homelab.kubernetes.loadBalancer.services.${name};
      };
    };
    spec = {
      type = "LoadBalancer";
      selector.app = name;
      ports = [
        {
          name = "http";
          port = 8080;
          targetPort = 8080;
        }
      ];
    };
  };

  kubernetes.resources.configMaps."${name}-config" = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    data."config.toml" = configToml;
  };

  kubernetes.resources.objectbucketclaim."${name}-s3" = {
    metadata = {
      inherit namespace;
    };
    spec = {
      inherit bucketName;
      storageClassName = "rook-ceph-objectstore";
    };
  };
}

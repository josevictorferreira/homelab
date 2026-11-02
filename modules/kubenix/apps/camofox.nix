{ homelab, ... }:

let
  name = "camofox";
  namespace = homelab.kubernetes.namespaces.applications;
  # Camofox: REST API server wrapping Camoufox (anti-detect Firefox).
  # Hermes talks to it natively via CAMOFOX_URL (browser.cloud_provider: camofox).
  image = "ghcr.io/jo-inc/camofox-browser:1.18.1@sha256:cff2c1432b609bde9c9d0b91e5b924dae0799d3c7bc9d468c0bc949325beaf2a";
  port = 9377;
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
            containers.${name} = {
              inherit image;
              # Kubernetes injects CAMOFOX_PORT=tcp://<svc-ip>:9377 from the Service
              # of the same name; the server parses that as its listen port (NaN).
              env = [
                {
                  name = "CAMOFOX_PORT";
                  value = toString port;
                }
              ];
              ports = [
                {
                  name = "http";
                  containerPort = port;
                }
              ];
              volumeMounts = [
                {
                  name = "devshm";
                  mountPath = "/dev/shm";
                }
              ];
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "500m";
                };
                limits = {
                  memory = "2Gi";
                  cpu = "2";
                };
              };
              readinessProbe = {
                httpGet = {
                  path = "/health";
                  inherit port;
                };
                initialDelaySeconds = 15;
                periodSeconds = 10;
              };
              livenessProbe = {
                httpGet = {
                  path = "/health";
                  inherit port;
                };
                initialDelaySeconds = 60;
                periodSeconds = 30;
              };
            };
            volumes = [
              {
                name = "devshm";
                emptyDir.medium = "Memory";
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
        selector.app = name;
        ports = [
          {
            name = "http";
            inherit port;
            targetPort = port;
          }
        ];
      };
    };
  };
}

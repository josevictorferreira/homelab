{ homelab, ... }:

let
  name = "cloakbrowser";
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
            containers.${name} = {
              image = "cloakhq/cloakbrowser:latest";
              command = [
                "sh"
                "-c"
                "touch /.dockerenv && exec cloakserve"
              ];
              ports = [
                {
                  name = "cdp";
                  containerPort = 9222;
                }
              ];
              volumeMounts = [
                {
                  name = "devshm";
                  mountPath = "/dev/shm";
                }
              ];
              securityContext.capabilities.add = [ "SYS_ADMIN" ];
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
                tcpSocket.port = 9222;
                initialDelaySeconds = 30;
                periodSeconds = 10;
              };
              # No liveness probe — cloakserve manages its own Chrome lifecycle
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
            name = "cdp";
            port = 9222;
            targetPort = 9222;
          }
        ];
      };
    };
  };
}

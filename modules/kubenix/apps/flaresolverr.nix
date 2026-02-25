{ homelab, ... }:

let
  name = "flaresolverr";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.deployments.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      replicas = 1;
      selector.matchLabels.app = name;
      template = {
        metadata.labels.app = name;
        spec = {
          terminationGracePeriodSeconds = 60;
          containers = [
            {
              inherit name;
              image = "ghcr.io/flaresolverr/flaresolverr:v3.4.6";
              ports = [
                {
                  name = "http";
                  containerPort = 8191;
                  protocol = "TCP";
                }
              ];
              env = [
                {
                  name = "PORT";
                  value = "8191";
                }
                {
                  name = "LOG_LEVEL";
                  value = "info";
                }
                {
                  name = "TZ";
                  value = "Etc/UTC";
                }
              ];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits = {
                  cpu = "2";
                  memory = "2Gi";
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
                  port = 8191;
                };
                initialDelaySeconds = 30;
                periodSeconds = 10;
              };
              readinessProbe = {
                tcpSocket = {
                  port = 8191;
                };
                initialDelaySeconds = 5;
                periodSeconds = 5;
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
    };
    spec = {
      type = "ClusterIP";
      selector.app = name;
      ports = [
        {
          name = "http";
          port = 8191;
          targetPort = 8191;
        }
      ];
    };
  };
}

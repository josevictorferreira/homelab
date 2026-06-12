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
              command = [ "cloakserve" ];
              ports = [
                {
                  name = "cdp";
                  containerPort = 9222;
                }
              ];
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "250m";
                };
                limits = {
                  memory = "1Gi";
                  cpu = "1";
                };
              };
              readinessProbe = {
                tcpSocket.port = 9222;
                initialDelaySeconds = 10;
                periodSeconds = 30;
              };
              livenessProbe = {
                tcpSocket.port = 9222;
                initialDelaySeconds = 15;
                periodSeconds = 30;
              };
            };
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

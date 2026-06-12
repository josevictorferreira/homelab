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
              env = [
                {
                  name = "CLOAKBROWSER_NO_SANDBOX";
                  value = "1";
                }
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
                  memory = "256Mi";
                  cpu = "250m";
                };
                limits = {
                  memory = "2Gi";
                  cpu = "2";
                };
              };
              readinessProbe = {
                httpGet = {
                  path = "/json/version";
                  port = 9222;
                };
                initialDelaySeconds = 15;
                periodSeconds = 30;
              };
              livenessProbe = {
                httpGet = {
                  path = "/json/version";
                  port = 9222;
                };
                initialDelaySeconds = 30;
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
            name = "cdp";
            port = 9222;
            targetPort = 9222;
          }
        ];
      };
    };
  };
}

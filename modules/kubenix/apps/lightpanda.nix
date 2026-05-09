{ homelab, ... }:

let
  name = "lightpanda";
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
              image = "lightpanda/browser:nightly";
              ports = [
                {
                  name = "cdp";
                  containerPort = 9222;
                  protocol = "TCP";
                }
              ];
              command = [
                "lightpanda"
                "serve"
                "--host"
                "0.0.0.0"
                "--port"
                "9222"
                "--timeout"
                "0"
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
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
              livenessProbe = {
                httpGet = {
                  path = "/json/version";
                  port = 9222;
                };
                initialDelaySeconds = 10;
                periodSeconds = 10;
              };
              readinessProbe = {
                httpGet = {
                  path = "/json/version";
                  port = 9222;
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
          name = "cdp";
          port = 9222;
          targetPort = 9222;
        }
      ];
    };
  };
}

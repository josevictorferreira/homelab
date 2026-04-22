{ homelab, ... }:

let
  name = "grafana-alert-relay";
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
          imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          containers.${name} = {
            inherit name;
            image = "ghcr.io/josevictorferreira/grafana-alert-relay:1.0.1";
            ports = [
              {
                name = "http";
                containerPort = 8080;
                protocol = "TCP";
              }
            ];
            envFrom = [
              {
                secretRef = {
                  name = "${name}-env";
                };
              }
            ];
            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "256Mi";
              };
            };
          };
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
          port = 8080;
          targetPort = 8080;
        }
      ];
    };
  };
}

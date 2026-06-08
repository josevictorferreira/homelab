{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "searxng";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://self-hosters-by-night.github.io/helm-charts";
        chart = "searxng";
        version = "1.1.0";
        sha256 = "sha256-8DA5H/PRXktku2u430ncar4UWcrHlQQQ1Jm1XnLlvm0=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        replicaCount = 1;

        image = {
          repository = "ghcr.io/searxng/searxng";
          tag = "2026.6.4-e6559c9ad";
          pullPolicy = "IfNotPresent";
        };

        ingress = kubenix.lib.ingressFor app;

        limiter = "";

        volumeMounts = [
          {
            name = "settings";
            mountPath = "/etc/searxng";
          }
        ];

        volumes = [
          {
            name = "settings";
            configMap = {
              name = "${app}-config";
              items = [
                {
                  key = "settings.yml";
                  path = "settings.yml";
                }
                {
                  key = "limiter.toml";
                  path = "limiter.toml";
                }
              ];
            };
          }
        ];
      };
    };

    resources = {
      deployments.${app} = {
        metadata.namespace = namespace;
        spec.template.spec.containers.${app} = {
          env = [
            {
              name = "SEARXNG_PORT";
              value = "8080";
            }
          ];
          envFrom = [
            {
              secretRef = {
                name = "searxng-secret";
              };
            }
          ];
        };
      };
    };
  };
}

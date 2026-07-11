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
          tag = "2026.6.20-fd42d4fda";
          pullPolicy = "IfNotPresent";
        };

        ingress = kubenix.lib.ingressFor app;

        limiter = "";

        resources = {
          requests = {
            cpu = "50m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "256Mi";
          };
        };

        affinity = homelab.kubernetes.affinities.piNode;
        tolerations = [
          {
            key = "pi-only";
            operator = "Equal";
            value = "true";
            effect = "NoSchedule";
          }
        ];
        extraVolumeMounts = [
          {
            name = "settings";
            mountPath = "/etc/searxng/settings.yml";
            subPath = "settings.yml";
            readOnly = true;
          }
          {
            name = "settings";
            mountPath = "/etc/searxng/limiter.toml";
            subPath = "limiter.toml";
            readOnly = true;
          }
        ];

        extraVolumes = [
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

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
        version = "1.3.1";
        sha256 = "sha256-cw1eIkNTe6TEHglBR7PkK5C61df9zELPOUzmj9pinf8=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        replicaCount = 1;

        image = {
          repository = "ghcr.io/searxng/searxng";
          # Multi-arch index for 2026.10.13-22c64b8d3 (the old pin was its
          # arm64-only manifest, from when searxng ran on the Pi).
          digest = "sha256:9b61996edcc679fb6665290f95fda15389a14eda6060e41a25c63ab2758f2436";
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

        # Not named "settings": chart 1.3 adds its own volume by that name
        # (default settings.yml) and would replace this one.
        extraVolumeMounts = [
          {
            name = "${app}-config";
            mountPath = "/etc/searxng/settings.yml";
            subPath = "settings.yml";
            readOnly = true;
          }
          {
            name = "${app}-config";
            mountPath = "/etc/searxng/limiter.toml";
            subPath = "limiter.toml";
            readOnly = true;
          }
        ];

        extraVolumes = [
          {
            name = "${app}-config";
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

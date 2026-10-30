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
          digest = "sha256:ef6ae36e01f89f8dadcabc684a9159728fbda6f0be8d638edce26d0a3ede17c6";
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

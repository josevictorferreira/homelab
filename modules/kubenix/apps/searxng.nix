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
        version = "1.0.0";
        sha256 = "sha256-JJNfXcKol5Ct0dOB2xkIdM3MYbgZh10DIP2x0c3S8XA=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        replicaCount = 1;

        image = {
          repository = "ghcr.io/searxng/searxng";
          tag = "latest@sha256:53f540d1f5481e737ec2c9eca529dc444c9cda49b63edecd3e75b069e5ec818e";
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

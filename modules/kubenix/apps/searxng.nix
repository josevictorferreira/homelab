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
      namespace = namespace;

      values = {
        replicaCount = 1;

        image = {
          repository = "ghcr.io/searxng/searxng";
          tag = "2026.2.16-8e824017d@sha256:60055af6f2f1ca14b488d9c0f47a019d1dbaf15b4f6547a7194253bf2ab94744";
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
            { secretRef.name = "searxng-secret"; }
          ];
        };
      };
    };
  };
}

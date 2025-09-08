{ k8sLib, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "searxng";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch {
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
          repository = "searxng/searxng";
          tag = "searxng/searxng:2025.9.5-e7501ea@sha256:511fa3f34c1d119c47f88c9a1e7eda1340f346543e980c17e5f14b27dac6a1ed";
        };

        service = k8sLib.plainServiceFor app;

        ingress = k8sLib.ingressFor app;
      };
    };
  };
}


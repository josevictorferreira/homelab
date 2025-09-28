{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "searxng";
  limiter = ''
    [botdetection]
    ipv4_prefix = 32
    ipv6_prefix = 48
    trusted_proxies = [
      '10.10.10.0/24',
      '10.42.0.0/24'
      '10.43.0.0/24'
    ]

    [botdetection.ip_limit]
    filter_link_local = false
    link_token = false

    [botdetection.ip_lists]
    block_ip = [
    ]
    pass_ip = [
    ]
    pass_searxng_org = true
  '';
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
          tag = "2025.9.27-87bc97776@sha256:50e3a9591c1e9ab223aed8f5b1cd2c34340b48c91fce74f3a077755f2900b479";
          pullPolicy = "IfNotPresent";
        };

        service = kubenix.lib.plainServiceFor app;

        ingress = kubenix.lib.ingressFor app;

        limiter = limiter;
      };
    };

    resources = {
      deployments.${app} = {
        metadata.namespace = namespace;
        spec.template.spec.containers.${app} = {
          env = [
            {
              name = "SEARXNG_UI_DEFAULT_LOCALE";
              value = "en-US";
            }
          ];
        };
      };
    };
  };
}


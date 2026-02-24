{ kubenix
, homelab
, ...
}:

let
  app = "uptimekuma";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.irsigler.cloud/";
        chart = "uptime-kuma";
        version = "2.22.0";
        sha256 = "sha256-eh42cO0bFiMNYIpXJSHkGQVnGsn4cmv6ju8VjYu8YYU=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = {
          repository = "louislam/uptime-kuma";
          pullPolicy = "IfNotPresent";
          tag = "2.1.1-slim@sha256:b0467ba27b6e9f14fe3b0f458b5415085cc22d58471431fc8f167952e9dc6442";
        };

        volume = {
          storageClassName = "rook-ceph-block";
        };

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = kubenix.lib.serviceAnnotationFor app;
          hosts = [
            {
              host = kubenix.lib.domainFor "uptimekuma";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [ (kubenix.lib.domainFor "uptimekuma") ];
              secretName = "wildcard-tls";
            }
          ];
        };
      };
    };
  };
}

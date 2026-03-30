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
      inherit namespace;

      values = {
        image = {
          repository = "louislam/uptime-kuma";
          pullPolicy = "IfNotPresent";
          tag = "2.2.1@sha256:7337368a77873f159435de9ef09567f68c31285ed5f951dec36256c4b267ee44";
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

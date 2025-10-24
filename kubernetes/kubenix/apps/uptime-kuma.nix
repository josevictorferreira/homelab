{
  kubenix,
  homelab,
  ...
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
          tag = "2.0.2-slim@sha256:60f3b7d1b55c3d5a9d941f7f91c3e7ac624dea53beb34538fe5546e3664a1e82";
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

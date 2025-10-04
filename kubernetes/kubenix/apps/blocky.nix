{
  kubenix,
  homelab,
  ...
}:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "blocky";
in
{
  submodules.instances."${app}" = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/0xerr0r/blocky";
        tag = "v0.26.1@sha256:969aeb8e573dee62c565c6e1f9604d44a367adfcf560edac4994b14af90f81a6";
        pullPolicy = "IfNotPresent";
      };
      subdomain = app;
      port = 4000;
      replicas = 3;
      config = { };
      values = {
        service.dns = {
          type = "LoadBalancer";
          annotations = kubenix.lib.serviceAnnotationFor app;
          ports = {
            dns = {
              enabled = true;
              protocol = "UDP";
              port = 53;
            };
            dnstcp = {
              enabled = true;
              protocol = "TCP";
              port = 53;
            };
          };
        };
        service.dot = {
          type = "LoadBalancer";
          annotations = kubenix.lib.serviceAnnotationFor app;
          ports = {
            dot = {
              enabled = true;
              protocol = "TCP";
              port = 853;
            };
          };
        };
        persistence.blocky = {
          type = "configMap";
          name = "blocky-config";
          items = [
            {
              key = "config.yml";
              path = "config.yml";
            }
          ];
          advancedMounts = {
            main.main = [
              {
                path = "/app/config.yml";
                readOnly = true;
                subPath = "config.yml";
              }
            ];
          };
        };
      };
    };
  };
}

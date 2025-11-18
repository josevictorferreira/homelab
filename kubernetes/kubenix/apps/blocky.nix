{ kubenix
, homelab
, ...
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
        tag = "v0.28.1@sha256:e9af552da2b0849f9b3b48ae3169acb2696fdf0ddc65df52e4025c9deef04a60";
        pullPolicy = "IfNotPresent";
      };
      port = 4000;
      replicas = 3;
      config = {
        filename = "config.yml";
        mountPath = "/app";
      };
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
      };
    };
  };
}

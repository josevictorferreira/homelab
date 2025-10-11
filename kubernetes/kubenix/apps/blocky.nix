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
        tag = "v0.27.0@sha256:d4bb3ad54b5b3471341d11609eabb8b3d9da0faf3244da7bb2d210107b2fbc30";
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

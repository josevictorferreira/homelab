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
      inherit namespace;
      image = {
        repository = "ghcr.io/0xerr0r/blocky";
        tag = "v0.35.0@sha256:4f165b63db0d76c96ecc47c7a8f57caeedc003a912bdce29abb0e283ce02e16b";
        pullPolicy = "IfNotPresent";
      };
      port = 4000;
      replicas = 3;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "256Mi";
        };
      };
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

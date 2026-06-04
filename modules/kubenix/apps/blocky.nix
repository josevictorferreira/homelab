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
        tag = "v0.31.0@sha256:2e5696efe4f920a9c07efa5587650fb94e7c4dc68759a77debde3daaa1e30cdb";
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

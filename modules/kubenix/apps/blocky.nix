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
        tag = "v0.28.3@sha256:5f84a54e4ee950c4ab21db905b7497476ece2f4e1a376d23ab8c4855cabddcba";
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

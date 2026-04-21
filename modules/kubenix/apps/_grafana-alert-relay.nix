{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "grafana-alert-relay";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/grafana-alert-relay";
        tag = "1.0.0@sha256:d59bfd19c3d9a3294555cb2f254ba87626077942b581737f5625117b132067df";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "256Mi";
        };
      };
      secretName = "${app}-env";
      values = {
        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];
        controllers.main.containers.main.env = {
          PORT = "8080";
        };
      };
    };
  };
}

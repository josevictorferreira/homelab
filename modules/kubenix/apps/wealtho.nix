{ homelab, kubenix, ... }:

let
  app = "wealtho";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/wealtho";
    tag = "latest";
    pullPolicy = "Always";
  };
  port = 3000;
  secretName = "${app}-config";
  pullSecrets = [{ name = "ghcr-registry-secret"; }];
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace image port secretName;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main.probes = {
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/up";
                port = port;
              };
              initialDelaySeconds = 30;
              periodSeconds = 10;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/up";
                port = port;
              };
              initialDelaySeconds = 5;
              periodSeconds = 5;
            };
          };
        };
      };
    };
  };
}

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
      waitFor = [ "postgres" ];
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
              # Puma needs > 60 s to bind on a capped 1.2 GHz node (lab-gamma-wk);
              # the previous 30 s + 3 x 10 s budget killed it in a loop (2026-09-16).
              initialDelaySeconds = 120;
              periodSeconds = 10;
              timeoutSeconds = 5;
              failureThreshold = 6;
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
              timeoutSeconds = 5;
            };
          };
        };
      };
    };
  };
}

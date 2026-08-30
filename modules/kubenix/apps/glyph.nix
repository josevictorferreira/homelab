{ homelab, kubenix, ... }:

let
  app = "glyph";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/glyph";
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
      inherit
        namespace
        image
        port
        secretName
        ;
      resources = {
        requests = {
          cpu = "100m";
          memory = "512Mi";
        };
        # Glyph runs agent steps and Solid Queue in Puma; allow enough memory/CPU for Pi child processes
        limits = {
          cpu = "2000m";
          memory = "4Gi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main.probes = {
          startup = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/up";
                inherit port;
              };
              initialDelaySeconds = 15;
              periodSeconds = 10;
              failureThreshold = 30;
            };
          };
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/up";
                inherit port;
              };
              periodSeconds = 30;
              timeoutSeconds = 5;
              failureThreshold = 3;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/up";
                inherit port;
              };
              periodSeconds = 10;
              timeoutSeconds = 5;
              failureThreshold = 3;
            };
          };
        };
      };
    };
  };
}

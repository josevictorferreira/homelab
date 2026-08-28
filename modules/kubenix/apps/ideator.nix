{ homelab, kubenix, ... }:

let
  app = "ideator";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/ideator";
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
          memory = "256Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main.probes = {
          # db:prepare + db:seed run in the entrypoint before Puma binds, so the
          # startup probe has to tolerate a schema load on a cold database.
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

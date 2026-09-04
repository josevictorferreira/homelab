{ homelab, kubenix, ... }:

let
  app = "foyer";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 8080;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];
  foyerConfigMap = (import ./foyer-config.enc.nix { inherit homelab kubenix; }).kubernetes.resources.configMaps."foyer".data;
  configHash = builtins.hashString "sha256" (foyerConfigMap."foyer.yml" + foyerConfigMap."custom.css");
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace port;
      image = {
        repository = "ghcr.io/josevictorferreira/foyer";
        tag = "latest";
        pullPolicy = "Always";
      };
      # Foyer uses separate persistent paths for its SQLite state and module
      # cache; the release's default /data volume is retained but unused.
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
      config = {
        filename = "foyer.yml";
        mountPath = "/app/config";
      };
      values = {
        controllers.main.pod.annotations."foyer.josevictor.me/config-hash" = configHash;
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main.probes = {
          startup = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/healthz";
                inherit port;
              };
              initialDelaySeconds = 5;
              periodSeconds = 5;
              failureThreshold = 30;
            };
          };
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/healthz";
                inherit port;
              };
              periodSeconds = 30;
              timeoutSeconds = 5;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/readyz";
                inherit port;
              };
              periodSeconds = 10;
              timeoutSeconds = 5;
            };
          };
        };
        # theme.custom_css_file points here; served by foyer at /custom.css.
        persistence.custom-css = {
          enabled = true;
          type = "configMap";
          name = app;
          items = [
            {
              key = "custom.css";
              path = "custom.css";
            }
          ];
          globalMounts = [
            {
              path = "/app/config/custom.css";
              subPath = "custom.css";
              readOnly = true;
            }
          ];
        };
        persistence.data = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data";
              readOnly = false;
            }
          ];
        };
        persistence.cache = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/cache";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}

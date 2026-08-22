{ homelab, kubenix, ... }:

let
  app = "bookorbit";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/bookorbit/bookorbit";
    tag = "latest@sha256:a2e1f5e59f9b1aec58116ced886d547f16af5d1da911c8e5b920d23b9826a96a";
    pullPolicy = "IfNotPresent";
  };
  port = 3000;
  secretName = "${app}-config";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
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
        limits = {
          cpu = "2";
          memory = "2Gi";
        };
      };
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = kubenix.lib.defaultStorageClass;
        size = "5Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/data";
            readOnly = false;
          }
        ];
      };
      values = {
        # Pod joins GID 100 (users) so the PUID=1000 file worker can write
        # to the shared CephFS books library (owned 10000:100, mode 2775).
        controllers.main.pod.securityContext.supplementalGroups = [ 100 ];
        controllers.main.containers.main.env = {
          APP_URL = "http://bookorbit.${homelab.domain}";
          CLIENT_URL = "http://bookorbit.${homelab.domain}";
          NODE_ENV = "production";
          PORT = "${toString port}";
          PUID = "1000";
          PGID = "1000";
          LIBRARY_BROWSE_ROOT = "/books";
          BOOK_DOCK_PATH = "/books";
          NODE_MAX_OLD_SPACE_SIZE = "2048";
        };
        controllers.main.containers.main.probes = {
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/health";
                port = port;
              };
              initialDelaySeconds = 30;
              periodSeconds = 15;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/health";
                port = port;
              };
              initialDelaySeconds = 15;
              periodSeconds = 10;
            };
          };
        };
        # Existing Calibre library shared on CephFS (subPath books)
        persistence.books = {
          enabled = true;
          type = "persistentVolumeClaim";
          existingClaim = kubenix.lib.sharedStorage.rootPVC;
          advancedMounts.main.main = [
            {
              path = "/books";
              subPath = "books";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}

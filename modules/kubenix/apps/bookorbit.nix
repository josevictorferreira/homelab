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
        # The shared CephFS Calibre library (/books) is owned 10000:100, mode
        # 2775 (setgid, group-writable). The image entrypoint re-execs via
        # `su-exec $PUID:$PGID`, which WIPES K8s supplementalGroups. Set PGID=100
        # so the app's PRIMARY group is 100 (survives su-exec) and it can write
        # books + cover images into the library.
        controllers.main.containers.main.env = {
          APP_URL = "http://bookorbit.${homelab.domain}";
          CLIENT_URL = "http://bookorbit.${homelab.domain}";
          NODE_ENV = "production";
          PORT = "${toString port}";
          PUID = "1000";
          PGID = "100";
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

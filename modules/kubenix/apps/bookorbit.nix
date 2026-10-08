{ homelab, kubenix, ... }:

let
  app = "bookorbit";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/bookorbit/bookorbit";
    tag = "3.3.0@sha256:4c2a1b957a3c8aeb9f59bb27a7d8efb18fa42c758afed3dcfc62620c5bcd1831";
    pullPolicy = "IfNotPresent";
  };
  port = 3000;
  secretName = "${app}-config";
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
          # 2026-10-06: startup is CPU-bound and ran past the liveness window
          # on a busy node (lab-alpha-cp saturated), crash-looping the pod.
          # Liveness and readiness only start once this passes (up to 10 min).
          startup = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/health";
                port = port;
              };
              periodSeconds = 10;
              failureThreshold = 60;
            };
          };
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

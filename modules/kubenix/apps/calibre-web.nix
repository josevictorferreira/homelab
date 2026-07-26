{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "calibre-web";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "crocodilestick/calibre-web-automated";
        tag = "latest@sha256:c31a738b6d5ec6982c050063dd3f063b6943eb1051fc81144789f840d9093a8d";
        pullPolicy = "IfNotPresent";
      };
      port = 8083;
      replicas = 1;
      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "1";
          memory = "1Gi";
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
            path = "/config";
            readOnly = false;
          }
        ];
      };
      values = {
        ingress.main.hosts = [
          {
            host = "calibre.${homelab.domain}";
            paths = [
              {
                path = "/";
                service.name = app;
                service.port = 8083;
              }
            ];
          }
        ];
        ingress.main.tls = [
          {
            secretName = kubenix.lib.defaultTLSSecret;
            hosts = [ "calibre.${homelab.domain}" ];
          }
        ];
        controllers.main.containers.main.env = {
          PUID = "1000";
          PGID = "1000";
          TZ = homelab.timeZone;
          NETWORK_SHARE_MODE = "true";
          CWA_PORT_OVERRIDE = "8083";
        };
        persistence.calibre-library = {
          enabled = true;
          type = "persistentVolumeClaim";
          existingClaim = kubenix.lib.sharedStorage.rootPVC;
          globalMounts = [
            {
              path = "/calibre-library";
              subPath = "books";
              readOnly = false;
            }
          ];
        };
        persistence.ingest = {
          enabled = true;
          type = "persistentVolumeClaim";
          existingClaim = kubenix.lib.sharedStorage.rootPVC;
          globalMounts = [
            {
              path = "/cwa-book-ingest";
              subPath = "book-ingest";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}

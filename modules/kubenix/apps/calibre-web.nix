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
        repository = "lscr.io/linuxserver/calibre-web";
        tag = "latest@sha256:18cd5d1d5c13b133fdf25506df8db415aee675ecf3ea01d086f01296a39666c4";
        pullPolicy = "IfNotPresent";
      };
      port = 8083;
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
        };
        persistence.books = {
          enabled = true;
          type = "persistentVolumeClaim";
          existingClaim = kubenix.lib.sharedStorage.rootPVC;
          globalMounts = [
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

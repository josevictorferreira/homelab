{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "readeck";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      waitFor = [ "postgres" ];
      inherit namespace;
      image = {
        repository = "codeberg.org/readeck/readeck";
        tag = "0.23.1@sha256:d1dde9c0a7292fffe4170ec410aeffb03d67693b41f954918aad8dc3dd70786b";
        pullPolicy = "IfNotPresent";
      };
      port = 8000;
      resources = {
        requests = {
          cpu = "200m";
          memory = "512Mi";
        };
        limits = {
          cpu = "1";
          memory = "2Gi";
        };
      };
      secretName = "readeck-env";
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = kubenix.lib.defaultStorageClass;
        size = "5Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/readeck";
            readOnly = false;
          }
        ];
      };
      values = {
        controllers.main.containers.main.env = {
          READECK_LOG_LEVEL = "info";
          READECK_LOG_FORMAT = "text";
          READECK_SERVER_HOST = "0.0.0.0";
          READECK_SERVER_PORT = "8000";
        };
      };
    };
  };
}

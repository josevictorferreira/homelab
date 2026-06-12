{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "readeck";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "codeberg.org/readeck/readeck";
        tag = "0.22.3@sha256:ed1c513f8e1d59b1d38fda324ac279eeb65afd0327907e498061ec9fd2f31c15";
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

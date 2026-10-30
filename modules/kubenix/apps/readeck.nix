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
        tag = "0.23.5@sha256:17dea468f4f713930338062f58a3a5e0d04e37d2961ddb827792e223f3db91b4";
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

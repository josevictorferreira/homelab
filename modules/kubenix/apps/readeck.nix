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
        tag = "0.22.2@sha256:13fc370031543af7de0dbab84b3476ade6b77570e8dfffddbebdd7bfb8ffb387";
        pullPolicy = "IfNotPresent";
      };
      port = 8000;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "256Mi";
        };
      };
      secretName = "readeck-env";
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
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
          HTTP_PROXY = "http://flaresolverr:8191";
          HTTPS_PROXY = "http://flaresolverr:8191";
          NO_PROXY = "127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,::1/128";
        };
      };
    };
  };
}

{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "omniroute";
in
{
  submodules.instances."${app}" = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/diegosouzapw/omniroute";
        tag = "3.8.26@sha256:60cbe2f4df921e4bb6b80cd7e73c0b2db7f16859604d74e2001c746c2c756d2c";
        pullPolicy = "IfNotPresent";
      };
      secretName = "${app}-env";
      port = 20128;
      resources = {
        limits = {
          cpu = "500m";
          memory = "1536Mi";
        };
        requests = {
          cpu = "250m";
          memory = "512Mi";
        };
      };

      values = {
        controllers.main.strategy = "Recreate";

        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];

        controllers.main.pod.securityContext = {
          fsGroup = 1000;
          runAsUser = 1000;
          runAsGroup = 1000;
        };
        persistence.data = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "5Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data";
              readOnly = false;
            }
          ];
        };
        persistence.data-home = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data-home";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}

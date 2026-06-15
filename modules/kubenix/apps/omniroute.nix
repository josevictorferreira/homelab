{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "omniroute";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/diegosouzapw/omniroute";
        tag = "3.8.25@sha256:7c0173e13816937d15f0cf9770b189c39ddbb48d54e48b662ef7632960a94130";
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

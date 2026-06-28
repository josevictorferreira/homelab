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
        tag = "3.8.39@sha256:1f756fd6d98234cb5dd8cb39a417bfd570548509af959a3f425151af749e8fb0";
        pullPolicy = "IfNotPresent";
      };
      secretName = "${app}-env";
      port = 20128;
      resources = {
        limits = {
          cpu = "500m";
          memory = "4Gi";
        };
        requests = {
          cpu = "250m";
          memory = "1Gi";
        };
      };

      values = {
        controllers.main.strategy = "Recreate";
        controllers.main.pod.annotations."omniroute.josevictor.me/memory-mb" = "3072";

        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];

        defaultPodOptions.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms =
          [
            {
              matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "NotIn";
                  values = [ "lab-gamma-wk" ];
                }
              ];
            }
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

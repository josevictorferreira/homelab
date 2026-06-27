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
        tag = "3.8.38@sha256:546761eb9f1290a3ff776ba5aa7468b479953604b92e602a1b30e023d6f397cd";
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

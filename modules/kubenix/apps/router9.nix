{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "router9";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        # repository = "ghcr.io/decolua/9router";
        repository = "ghcr.io/josevictorferreira/9router";
        tag = "5f8956f";
        pullPolicy = "IfNotPresent";
      };
      secretName = "${app}-env";
      port = 20128;

      values = {
        controllers.main.strategy = "Recreate";

        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];

        persistence.data = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
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

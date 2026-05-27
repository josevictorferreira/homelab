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
        repository = "ghcr.io/decolua/9router";
        tag = "0.4.63@sha256:7d916c3725a833c15abba368d7249774f03fc22f8e98a65855de19593d8a0055";
        pullPolicy = "IfNotPresent";
      };
      secretName = "${app}-env";
      port = 20128;

      values = {
        controllers.main.strategy = "Recreate";

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

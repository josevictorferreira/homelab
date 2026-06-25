{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "degoog";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/degoog-org/degoog";
        tag = "latest@sha256:4b3ba6fe7ab6c5ca76ce8aedbd5d07da7423d1043613fae94ff9f1c8acced479";
        pullPolicy = "Always";
      };
      port = 4444;
      replicas = 0;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
      persistence = {
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

      values = {
        defaultPodOptions.affinity = homelab.kubernetes.affinities.piNode;
        defaultPodOptions.tolerations = [
          {
            key = "pi-only";
            operator = "Equal";
            value = "true";
            effect = "NoSchedule";
          }
        ];
      };
    };
  };
}

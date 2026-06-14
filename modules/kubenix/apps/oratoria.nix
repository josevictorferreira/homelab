{ homelab, kubenix, ... }:

let
  app = "oratoria";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/oratoria";
        tag = "latest@sha256:4f7dc284a94e9961b002c0879dc2655551674c262eb46f1f532780f9ad211a75";
        pullPolicy = "Always";
      };
      port = 5173;
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
        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];
        controllers.main.containers.main.ports = [
          {
            name = "http";
            containerPort = 5173;
            protocol = "TCP";
          }
          {
            name = "backend";
            containerPort = 8765;
            protocol = "TCP";
          }
        ];
      };
    };
  };
}

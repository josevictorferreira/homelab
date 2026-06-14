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
        tag = "latest@sha256:614f61025b27dce29391cd8e820ca8f1a00304c5076a553ca584d7f84ea9d6f9";
        pullPolicy = "Always";
      };
      port = 8765;
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
        controllers.main.containers.main.ports = [
          {
            name = "http";
            containerPort = 8765;
            protocol = "TCP";
          }
          {
            name = "dev";
            containerPort = 5173;
            protocol = "TCP";
          }
        ];
        service.main.ports.dev = {
          enabled = true;
          port = 5173;
        };
      };
    };
  };
}

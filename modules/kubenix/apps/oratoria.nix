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
        tag = "latest@sha256:6845c73ac52e54e3acb08fb94c83ee9f06393d315faaca549430c1abd3a93dc3";
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
        controllers.main.containers.main = {
          envFrom = [
            { secretRef.name = "${app}-config"; }
          ];
          ports = [
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
        persistence.vite-config = {
          type = "configMap";
          name = "${app}-vite-config";
          advancedMounts.main.main = [
            {
              path = "/app/oratoria-web/vite.config.js";
              subPath = "vite.config.js";
              readOnly = true;
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.configMaps."${app}-vite-config" = {
    metadata = {
      name = "${app}-vite-config";
      inherit namespace;
    };
    data."vite.config.js" = ''
      const proxy = { '/api': 'http://127.0.0.1:8765' }
      export default {
        server: { proxy },
        preview: { proxy, allowedHosts: ["oratoria.josevictor.me"] },
        optimizeDeps: { include: ['oidc-client-ts'] },
      }
    '';
  };
}

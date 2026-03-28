{ kubenix, homelab, ... }:

let
  # Use root PVC with subPath to avoid overlapping CephFS mount issues
  immichLibraryPVC = "cephfs-shared-storage-root";
  app = "immich";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/immich-app/immich-charts/immich";
        chart = "immich";
        version = "0.10.3";
        sha256 = "sha256-+GGHO1w55A5/oe5gp/lweWXBMy7a/2VdoxlEdlsVnzk=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        controllers.main.containers.main = {
          env = { };
          envFrom = [
            {
              secretRef = {
                name = "immich-secret";
              };
            }
          ];
        };

        immich = {
          persistence.library = {
            existingClaim = immichLibraryPVC;
          };

          configuration = {
            trash.enabled = true;
            trash.days = 30;
          };

          metrics.enabled = true;
        };

        machine-learning = {
          enabled = true;

          controllers.main.containers.main = {
            image = {
              repository = "ghcr.io/immich-app/immich-machine-learning";
              tag = "v2.6.3@sha256:33b17015c3d14f2565e9b8cd36b48a70027b14b5cd20da7fbfff21a370b0309c";
              pullPolicy = "IfNotPresent";
            };
            resources = {
              requests = {
                cpu = "100m";
                memory = "256Mi";
              };
              limits = {
                cpu = "500m";
                memory = "1Gi";
              };
            };
          };

          env.TRANSFORMERS_CACHE = "/cache";

          persistence.cache = {
            enabled = true;
            size = "20Gi";
            type = "persistentVolumeClaim";
            accessMode = "ReadWriteOnce";
            storageClass = "rook-ceph-block";
          };
        };

        server = {
          enabled = true;
          controllers.main.containers.main = {
            image = {
              repository = "ghcr.io/immich-app/immich-server";
              tag = "v2.6.3@sha256:0cc1f82953d9598eb9e9dd11cbde1f50fe54f9c46c4506b089e8ad7bfc9d1f0c";
              pullPolicy = "IfNotPresent";
            };
            resources = {
              requests = {
                cpu = "100m";
                memory = "256Mi";
              };
              limits = {
                cpu = "500m";
                memory = "1Gi";
              };
            };
          };

          service.main = {
            enabled = true;
            type = "LoadBalancer";
            annotations = kubenix.lib.serviceAnnotationFor app;
          };

          ingress.main = {
            enabled = true;
            className = "cilium";
            hosts = [
              {
                host = kubenix.lib.domainFor app;
                paths = [
                  {
                    path = "/";
                    service.name = "immich-server";
                    service.port = 2283;
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = "wildcard-tls";
                hosts = [ (kubenix.lib.domainFor app) ];
              }
            ];
          };
        };
      };
    };
  };
}

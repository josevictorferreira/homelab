{ kubenix, homelab, ... }:

let
  # Use root PVC with subPath to avoid overlapping CephFS mount issues
  immichLibraryPVC = kubenix.lib.sharedStorage.rootPVC;
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
              tag = "v2.7.2@sha256:2f381909ca2b669f22bf872ee0bea6b7d16dfce109431647a8cad0f2571ff053";
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
            storageClass = kubenix.lib.defaultStorageClass;
          };
        };

        server = {
          enabled = true;
          controllers.main.containers.main = {
            image = {
              repository = "ghcr.io/immich-app/immich-server";
              tag = "v2.7.2@sha256:6a2952539e2a9c8adcf6fb74850bb1ba7e1db2804050acea21baafdc9154c430";
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
            className = kubenix.lib.defaultIngressClass;
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
                secretName = kubenix.lib.defaultTLSSecret;
                hosts = [ (kubenix.lib.domainFor app) ];
              }
            ];
          };
        };
      };
    };
  };
}

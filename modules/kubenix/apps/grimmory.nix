{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "grimmory";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "grimmory/grimmory";
        tag = "latest";
        pullPolicy = "IfNotPresent";
      };
      port = 6060;
      replicas = 1;
      secretName = "grimmory-config";
      resources = {
        requests = {
          cpu = "250m";
          memory = "512Mi";
        };
        limits = {
          cpu = "2";
          memory = "2Gi";
        };
      };
      persistence = {
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
      values = {
        ingress.main.hosts = [
          {
            host = "grimmory.${homelab.domain}";
            paths = [
              {
                path = "/";
                service.name = app;
                service.port = 6060;
              }
            ];
          }
        ];
        ingress.main.tls = [
          {
            secretName = kubenix.lib.defaultTLSSecret;
            hosts = [ "grimmory.${homelab.domain}" ];
          }
        ];
        controllers.main.containers.main.env = {
          DATABASE_URL = "jdbc:mariadb://grimmory-mariadb.${namespace}.svc.cluster.local:3306/grimmory";
          DATABASE_USERNAME = "grimmory";
          TZ = homelab.timeZone;
        };
        controllers.main.containers.main.probes = {
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/healthcheck";
                port = 6060;
              };
              initialDelaySeconds = 60;
              periodSeconds = 30;
              timeoutSeconds = 10;
              failureThreshold = 5;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/healthcheck";
                port = 6060;
              };
              initialDelaySeconds = 30;
              periodSeconds = 10;
              timeoutSeconds = 5;
              failureThreshold = 5;
            };
          };
          startup = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/api/v1/healthcheck";
                port = 6060;
              };
              initialDelaySeconds = 10;
              periodSeconds = 15;
              timeoutSeconds = 5;
              failureThreshold = 30;
            };
          };
        };
        persistence = {
          books = {
            enabled = true;
            type = "persistentVolumeClaim";
            existingClaim = kubenix.lib.sharedStorage.rootPVC;
            globalMounts = [
              {
                path = "/books";
                subPath = "books";
                readOnly = false;
              }
            ];
          };
          bookdrop = {
            enabled = true;
            type = "persistentVolumeClaim";
            existingClaim = kubenix.lib.sharedStorage.rootPVC;
            globalMounts = [
              {
                path = "/bookdrop";
                subPath = "books";
                readOnly = false;
              }
            ];
          };
        };
      };
    };
  };
}

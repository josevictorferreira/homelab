{ kubenix, homelab, ... }:

let
  app = "mautrix-whatsapp";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      persistentVolumeClaims.${app} = {
        metadata = { inherit namespace; };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          storageClassName = "rook-ceph-block";
          resources.requests.storage = "1Gi";
        };
      };

      services.${app} = {
        metadata = { inherit namespace; };
        spec = {
          selector = { inherit app; };
          ports = [
            {
              name = "http";
              port = 29318;
              targetPort = 29318;
            }
          ];
        };
      };

      configMaps."${app}-config" = {
        metadata = { inherit namespace; };
        data = {
          "config.yaml" = kubenix.lib.toYamlStr {
            homeserver = {
              address = "http://synapse.${namespace}.svc.cluster.local:8008";
              domain = "josevictor.me";
            };
            appservice = {
              address = "http://${app}.${namespace}.svc.cluster.local:29318";
              hostname = "0.0.0.0";
              port = 29318;
              # Database is provided via environment variable MAUTRIX_WHATSAPP_POSTGRES_URI
              database = "postgres://will-be-overridden-by-env";
            };
            bridge = {
              relay = {
                enabled = true;
              };
            };
            logging = {
              directory = "/data/logs";
              print_level = "info";
            };
          };
        };
      };

      deployments.${app} = {
        metadata = { inherit namespace; };
        spec = {
          replicas = 1;
          selector.matchLabels = { inherit app; };
          template = {
            metadata.labels = { inherit app; };
            spec = {
              imagePullSecrets = [
                { name = "mau-registry-secret"; }
              ];
              containers = [
                {
                  name = app;
                  image = "dock.mau.dev/mautrix/whatsapp:v0.11.1";
                  env = [
                    {
                      name = "MAUTRIX_WHATSAPP_DATABASE_URI";
                      valueFrom.secretKeyRef = {
                        name = "mautrix-whatsapp-env";
                        key = "MAUTRIX_WHATSAPP_POSTGRES_URI";
                      };
                    }
                  ];
                  ports = [
                    {
                      name = "http";
                      containerPort = 29318;
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/data";
                    }
                    {
                      name = "config";
                      mountPath = "/data/config.yaml";
                      subPath = "config.yaml";
                      readOnly = true;
                    }
                    {
                      name = "registration";
                      mountPath = "/data/registration.yaml";
                      subPath = "registration.yaml";
                      readOnly = true;
                    }
                  ];
                }
              ];
              volumes = [
                {
                  name = "data";
                  persistentVolumeClaim.claimName = app;
                }
                {
                  name = "config";
                  configMap.name = "${app}-config";
                }
                {
                  name = "registration";
                  secret.secretName = "mautrix-whatsapp-registration";
                }
              ];
            };
          };
        };
      };
    };
  };
}

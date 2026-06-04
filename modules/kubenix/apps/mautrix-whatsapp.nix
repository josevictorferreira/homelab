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
          storageClassName = kubenix.lib.defaultStorageClass;
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
              initContainers = [
                {
                  name = "copy-config";
                  image = "busybox:1.37";
                  command = [
                    "sh"
                    "-c"
                    ''
                      cp /config-src/config.yaml /data/config.yaml
                      cp /registration-src/registration.yaml /data/registration.yaml
                      chmod 644 /data/config.yaml /data/registration.yaml
                    ''
                  ];
                  resources = {
                    limits = {
                      cpu = "50m";
                      memory = "64Mi";
                    };
                    requests = {
                      cpu = "50m";
                      memory = "64Mi";
                    };
                  };
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/data";
                    }
                    {
                      name = "config";
                      mountPath = "/config-src";
                      readOnly = true;
                    }
                    {
                      name = "registration";
                      mountPath = "/registration-src";
                      readOnly = true;
                    }
                  ];
                }
              ];
              containers = [
                {
                  name = app;
                  image = "dock.mau.dev/mautrix/whatsapp:v0.2605.0@sha256:d126438cc0eb989c31ff32ab66a95a16d1fc47198eaabcba0fb4f4672e7a3412";
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
                  ];
                  resources = {
                    requests = {
                      cpu = "100m";
                      memory = "256Mi";
                    };
                    limits = {
                      cpu = "500m";
                      memory = "512Mi";
                    };
                  };
                }
              ];
              volumes = [
                {
                  name = "data";
                  persistentVolumeClaim.claimName = app;
                }
                {
                  name = "config";
                  secret.secretName = "mautrix-whatsapp-config";
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

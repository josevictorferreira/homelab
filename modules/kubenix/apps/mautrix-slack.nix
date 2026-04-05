{ kubenix, homelab, ... }:

let
  app = "mautrix-slack";
  dataPvcName = "${app}-v2";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      persistentVolumeClaims.${dataPvcName} = {
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
              port = 29333;
              targetPort = 29333;
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
                  image = "dock.mau.dev/mautrix/slack:v0.2603.0@sha256:09dc71b16a1d13cd3646ebf7aac4bc4b5f6445f746ee75d5540de92c145c97b4";
                  ports = [
                    {
                      name = "http";
                      containerPort = 29333;
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
                  persistentVolumeClaim.claimName = dataPvcName;
                }
                {
                  name = "config";
                  secret.secretName = "mautrix-slack-config";
                }
                {
                  name = "registration";
                  secret.secretName = "mautrix-slack-registration";
                }
              ];
            };
          };
        };
      };
    };
  };
}

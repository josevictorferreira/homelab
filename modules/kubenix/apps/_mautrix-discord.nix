{ kubenix, homelab, ... }:

let
  app = "mautrix-discord";
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
              port = 29334;
              targetPort = 29334;
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
                  image = "dock.mau.dev/mautrix/discord:v0.7.3";
                  ports = [
                    {
                      name = "http";
                      containerPort = 29334;
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/data";
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
                  secret.secretName = "mautrix-discord-config";
                }
                {
                  name = "registration";
                  secret.secretName = "mautrix-discord-registration";
                }
              ];
            };
          };
        };
      };
    };
  };
}

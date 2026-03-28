{ homelab, ... }:

let
  app = "mautrix-discord";
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
                  image = "dock.mau.dev/mautrix/discord:v0.7.6@sha256:965b25cb81e7c8133d2adda9057f9fd4c25bd645f1649d8d91129edfeb79d53d";
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

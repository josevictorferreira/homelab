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
                  image = "dock.mau.dev/mautrix/whatsapp:v0.2601.0";
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

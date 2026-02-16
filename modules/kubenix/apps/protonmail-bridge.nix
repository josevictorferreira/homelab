{ kubenix, homelab, ... }:

let
  app = "protonmail-bridge";
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
              name = "smtp";
              port = 25;
              targetPort = 25;
            }
            {
              name = "imap";
              port = 143;
              targetPort = 143;
            }
          ];
        };
      };

      statefulSets.${app} = {
        metadata = { inherit namespace; };
        spec = {
          replicas = 1;
          serviceName = app;
          selector.matchLabels = { inherit app; };
          template = {
            metadata.labels = { inherit app; };
            spec = {
              containers = [
                {
                  name = app;
                  image = "shenxn/protonmail-bridge:build";
                  ports = [
                    {
                      name = "smtp";
                      containerPort = 25;
                    }
                    {
                      name = "imap";
                      containerPort = 143;
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/root";
                    }
                  ];
                  resources = {
                    requests = {
                      memory = "256Mi";
                      cpu = "100m";
                    };
                    limits = {
                      memory = "512Mi";
                      cpu = "500m";
                    };
                  };
                  readinessProbe = {
                    tcpSocket.port = 143;
                    initialDelaySeconds = 10;
                    periodSeconds = 10;
                  };
                }
              ];
              volumes = [
                {
                  name = "data";
                  persistentVolumeClaim.claimName = app;
                }
              ];
            };
          };
        };
      };
    };
  };
}

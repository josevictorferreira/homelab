{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  pvcName = "cephfs-shared-storage";
  appName = "cephfs-smb-export";
in
{
  kubernetes.resources = {
    deployments.${appName} = {
      metadata = {
        name = appName;
        labels = {
          app = appName;
        };
      };
      spec = {
        replicas = 1;
        selector = {
          matchLabels = {
            app = appName;
          };
        };
        template = {
          metadata = {
            labels = {
              app = appName;
            };
          };
          spec = {
            containers = [
              {
                name = "samba";
                image = "ghcr.io/crazy-max/samba:4.21.4";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  { name = "smb"; containerPort = 445; protocol = "TCP"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/data/config.yml"; subPath = "config.yml"; }
                  { name = "share"; mountPath = "/samba/share"; }
                ];
                env = [
                  { name = "TZ"; value = homelab.timeZone; }
                  { name = "SAMBA_LOG_LEVEL"; value = "0"; }
                ];
              }
            ];
            volumes = [
              { name = "config"; configMap.name = "${appName}-config"; }
              { name = "share"; persistentVolumeClaim.claimName = pvcName; }
            ];
          };
        };
      };
    };

    services.${appName} = {
      metadata = {
        name = appName;
        inherit namespace;
        labels = {
          app = appName;
        };
      };
      spec = {
        type = "LoadBalancer";
        selector = {
          app = appName;
        };
        ports = [
          { name = "smb"; port = 445; targetPort = 445; protocol = "TCP"; }
        ];
      };
    };
  };
}

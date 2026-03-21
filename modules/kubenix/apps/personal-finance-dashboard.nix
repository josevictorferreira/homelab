{ kubenix, homelab, ... }:

let
  name = "personal-finances";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.deployments.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      replicas = 1;
      selector.matchLabels.app = name;
      template = {
        metadata = {
          labels.app = name;
        };
        spec = {
          imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          containers = [
            {
              inherit name;
              image = "ghcr.io/josevictorferreira/personal-finances:9a837aa";
              imagePullPolicy = "IfNotPresent";
              ports = [
                {
                  name = "http";
                  containerPort = 80;
                  protocol = "TCP";
                }
              ];
              volumeMounts = [
                {
                  name = "cephfs";
                  mountPath = "/shared";
                  readOnly = true;
                }
              ];
            }
          ];
          volumes = [
            {
              name = "cephfs";
              persistentVolumeClaim.claimName = "cephfs-shared-storage-root";
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.services.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      type = "ClusterIP";
      selector.app = name;
      ports = [
        {
          name = "http";
          port = 80;
          targetPort = "http";
          protocol = "TCP";
        }
      ];
    };
  };

  kubernetes.resources.ingresses.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      ingressClassName = "cilium";
      rules = [
        {
          host = "personal-finances.josevictor.me";
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = name;
                    port.number = 80;
                  };
                };
              }
            ];
          };
        }
      ];
      tls = [
        {
          hosts = [ "personal-finances.josevictor.me" ];
          secretName = "wildcard-tls";
        }
      ];
    };
  };
}

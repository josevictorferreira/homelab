{ kubenix, homelab, ... }:

let
  name = "personal-finances";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources = {
    deployments.${name} = {
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
                image = "ghcr.io/josevictorferreira/personal-finances@sha256:cfea2d3fdb63672711bdf1ad31c11a627416e889ec75262fe27972da2e391a50";
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
                persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
              }
            ];
          };
        };
      };
    };

    services.${name} = {
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

    ingresses.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        ingressClassName = kubenix.lib.defaultIngressClass;
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
                      inherit name;
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
            secretName = kubenix.lib.defaultTLSSecret;
          }
        ];
      };
    };
  };
}

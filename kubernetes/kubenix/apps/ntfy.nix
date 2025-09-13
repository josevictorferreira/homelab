{ kubenix, homelab, ... }:

let
  app = "ntfy";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/fmjstudios/helm/ntfy";
        chart = "ntfy";
        version = "0.2.2";
        sha256 = "sha256-AVvangTTMY1rakFqTOffJYjuuBPAoGNltCkooWKYmHk=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = {
          registry = "docker.io";
          repository = "binwiederhier/ntfy";
          tag = "v2.11.0";
          pullPolicy = "IfNotPresent";
        };

        ntfy = {
          baseURL = "https://${kubenix.lib.domainFor app}";
          listenHTTP = ":80";
          behindProxy = true;
          web = {
            existingSecret = "ntfy-secrets";
            file = "/data/webpush.db";
            emailAddress = "alerts@${homelab.domain}";
          };
          data = {
            rootPath = "/data";
            pvc = {
              size = "5Gi";
              storageClass = "rook-ceph-block";
            };
          };
          upstream.baseURL = "https://ntfy.sh";
          log.level = "info";
          cache.file = "/data/cache.db";
          attachment = {
            cacheDir = "/data/attachments";
            totalSizeLimit = "5G";
            fileSizeLimit = "15M";
            expiryDuration = "3h";
          };
        };

        service = {
          ports = {
            http = 80;
            https = 80;
          };
        };
      };
    };
    
    resources.ingresses.${app} = {
      metadata.name = app;
      metadata.namespace = namespace;
      metadata.annotations = {
        "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
      };
      spec = {
        ingressClassName = "cilium";
        rules = [
          {
            host = kubenix.lib.domainFor app;
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service.name = "ntfy";
                backend.service.port.number = 80;
              }
            ];
          }
        ];
        tls = [
          {
            hosts = [
              (kubenix.lib.domainFor app)
            ];
            secretName = "wildcard-tls";
          }
        ];
      };
    };

    resources.statefulSets.ntfy.spec = {
      serviceName = "ntfy";
      template.spec = {
        containers.ntfy = {
          args = [ "serve" "--config" "/var/lib/ntfy/config.yml" ];
        };
      };
    };

  };
}

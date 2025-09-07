{ k8sLib, homelab, ... }:

let
  app = "ntfy";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch {
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
          baseURL = k8sLib.domainFor app;
          listenHTTP = ":80";
          behindProxy = true;
          serviceAccount.name = "ntfy";
          serviceName = "ntfy";
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

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          tls = [
            {
              hosts = [ (k8sLib.domainFor app) ];
              secretName = "wildcard-tls";
            }
          ];
        };
      };
    };

    resources.statefulSets.ntfy.spec = {
      serviceName = "ntfy";
      template.spec = {
        # volumes.ntfy-config = {
        #   name = "ntfy-config";
        #   configMap = {
        #     name = "ntfy";
        #     items = [
        #       {
        #         key = "config.yml";
        #         path = "config.yml";
        #       }
        #     ];
        #   };
        # };
        containers.ntfy = {
          args = [ "serve" "--config" "/var/lib/ntfy/config.yml" ];
          # volumeMounts.ntfy-config = {
          #   name = "ntfy-config";
          #   mountPath = "/var/lib/ntfy/config.yml";
          #   subPath = "config.yml";
          # };
        };
      };
    };

  };
}

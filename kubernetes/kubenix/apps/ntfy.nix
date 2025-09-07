{ k8sLib, homelab, ... }:

let
  app = "ntfy";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch {
        repo = "https://fmjstudios.github.io/helm-charts/";
        chart = "ntfy";
        version = "0.2.2";
        sha256 = "sha256-qFG0Iq2IBwkqG6t2Z47GDU3fjftzy3xI7ALNJjctNQk=";
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
          baseURL = "ntfy.${homelab.domain}";
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

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          tls = [
            {
              hosts = [ "ntfy.${homelab.domain}" ];
              secretName = "wildcard-tls";
            }
          ];
        };
      };
    };
  };
}

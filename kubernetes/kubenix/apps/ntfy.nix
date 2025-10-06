{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "ntfy";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "docker.io/binwiederhier/ntfy";
        tag = "v2.14.0@sha256:5a051798d14138c3ecb12c038652558ab6a077e1aceeb867c151cbf5fa8451ef";
        pullPolicy = "IfNotPresent";
      };
      subdomain = app;
      port = 80;
      secretName = "ntfy-secrets";
      command = [
        "ntfy"
        "serve"
        "--config"
        "/var/lib/ntfy/config.yml"
      ];
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
        size = "1Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/data";
            readOnly = false;
          }
        ];
      };
      config = {
        filename = "config.yml";
        mountPath = "/var/lib/ntfy";
        data = {
          base-url = "https://${kubenix.lib.domainFor app}";
          listen-http = ":80";
          web-root = "/";
          global-topic-limit = 15000;
          behind-proxy = true;
          cache-file = "/data/cache.db";
          auth-default-access = "deny-all";
          attachment-cache-dir = "/data/attachments";
          attachment-total-size-limit = "5G";
          attachment-file-size-limit = "15M";
          attachment-expiry-duration = "3h";
          web-push-file = "/data/webpush.db";
          web-push-email-address = "alerts@josevictor.me";
          upstream-base-url = "https://ntfy.sh";
          visitor-subscription-limit = 30;
          visitor-request-limit-burst = 60;
          visitor-request-limit-replenish = "5s";
          visitor-message-daily-limit = 15000;
          visitor-email-limit-burst = 16;
          visitor-email-limit-replenish = "1h";
          visitor-attachment-total-size-limit = "100M";
          visitor-attachment-daily-bandwidth-limit = "500M";
          metrics-listen-http = ":9090";
          log-level = "info";
          log-format = "text";
        };
      };
    };
  };
}

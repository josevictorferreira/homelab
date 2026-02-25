{ kubenix, homelab, ... }:

let
  app = "n8n";
  secretName = "${app}-env";
  bucketName = "n8n-files";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://community-charts.github.io/helm-charts";
        chart = "n8n";
        version = "1.15.5";
        sha256 = "sha256-1GiNnh/wuLx+ubKzd2o+hH0/9TO3yOA5A9re2AVlUNE=";
      };
      includeCRDs = true;
      noHooks = false;
      inherit namespace;

      values = {
        image = {
          repository = "n8nio/n8n";
          tag = "2.8.3@sha256:53004142b0e93de1e9e31943e601ed9bd4b24ca82a307864ccadf1820b627e5e";
          pullPolicy = "IfNotPresent";
        };

        db = {
          type = "postgresdb";
        };

        versionNotifications = {
          enabled = false;
        };

        timezone = homelab.timeZone;
        defaultLocale = "en";

        existingEncryptionKeySecret = secretName;

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          hosts = [
            {
              host = kubenix.lib.domainFor app;
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
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

        service = {
          enabled = true;
          type = "ClusterIP";
          port = 5678;
          name = "http";
        };

        main = {
          forceToUseStatefulset = false;

          persistence = {
            enabled = true;
            storageClass = "rook-ceph-block";
            accessMode = "ReadWriteOnce";
            size = "8Gi";
            mountPath = "/home/node/.n8n";
            annotations = {
              "helm.sh/resource-policy" = "keep";
            };
          };
        };

        redis.enabled = false;
        externalRedis = {
          host = "redis-headless";
          existingSecret = secretName;
        };

        postgresql.enabled = false;
        externalPostgresql = {
          host = "postgresql-18-hl";
          existingSecret = secretName;
        };

        serviceMonitor = {
          enabled = false;
        };
      };
    };

    resources.objectbucketclaim."n8n-s3" = {
      metadata = {
        inherit namespace;
      };
      spec = {
        inherit bucketName;
        storageClassName = "rook-ceph-objectstore";
      };
    };
  };
}

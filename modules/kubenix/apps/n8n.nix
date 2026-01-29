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
      namespace = namespace;

      values = {
        image = {
          repository = "n8nio/n8n";
          tag = "2.6.2@sha256:ff6fe9eca746b7455c9e6e4fbc6f5753c3204e82279e015fa62f1bfe309e6343";
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
        namespace = namespace;
      };
      spec = {
        bucketName = bucketName;
        storageClassName = "rook-ceph-objectstore";
      };
    };
  };
}

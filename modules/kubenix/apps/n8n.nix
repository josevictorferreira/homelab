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
        version = "1.15.19";
        sha256 = "sha256-TODO-Get-actual-sha256-for-1.15.19";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repository = "n8nio/n8n";
          tag = "1.117.3@sha256:TODO-Get-actual-digest-for-1.117.3";
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

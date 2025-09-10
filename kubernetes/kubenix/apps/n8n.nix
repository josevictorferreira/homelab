{ kubenix, homelab, ... }:

let
  app = "n8n";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://community-charts.github.io/helm-charts";
        chart = "n8n";
        version = "1.15.5";
        sha256 = "sha256-qFG0Iq2IBwkqG6t2Z47GDU3fjftzy3xI7ALNJjctNQk=";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repository = "n8nio/n8n";
          pullPolicy = "IfNotPresent";
        };

        db = { type = "postgresdb"; };

        versionNotifications = { enabled = false; };

        timezone = homelab.timeZone;
        defaultLocale = "en";

        ingress = {
          enabled = true;
          class = "cilium";
          host = kubenix.lib.domainFor "n8n";
          tls = true;
          existingSecret = "wildcard-tls";
        };

        service = {
          enabled = true;
          type = "ClusterIP";
          port = 5678;
          name = "http";
        };

        main = {
          pdb = { enabled = true; minAvailable = 1; };
          livenessProbe = { httpGet = { path = "/healthz";        port = "http"; }; };
          readinessProbe = { httpGet = { path = "/healthz/readiness"; port = "http"; }; };
          forceToUseStatefulset = false;

          persistence = {
            enabled = true;
            storageClass = "rook-ceph-block";
            accessMode = "ReadWriteOnce";
            size = "8Gi";
            mountPath = "/home/node/.n8n";
            annotations = { "helm.sh/resource-policy" = "keep"; };
          };

          extraEnvFrom = [
            { secretRef = { name = secretName; }; }
          ];
        };

        worker = {
          mode = "regular";
          pdb = { enabled = true; minAvailable = 1; };
          livenessProbe = { httpGet = { path = "/healthz"; port = "http"; }; };
          readinessProbe = { httpGet = { path = "/healthz/readiness"; port = "http"; }; };
          extraEnvFrom = [
            { secretRef = { name = secretName; }; }
          ];
        };

        webhook = {
          mode = "regular";
          pdb = { enabled = true; minAvailable = 1; };
          livenessProbe = { httpGet = { path = "/healthz"; port = "http"; }; };
          readinessProbe = { httpGet = { path = "/healthz/readiness"; port = "http"; }; };
          extraEnvFrom = [
            { secretRef = { name = secretName; }; }
          ];
        };

        binaryData = {
          mode = "filesystem";
          localStoragePath = "/home/node/.n8n";
        };

        redis.enabled = false;
        externalRedis = {
          host = "redis-headless";
          existingSecret = secretName;
        };

        postgresql.enabled = false;
        externalPostgresql =  {
          host = "postgresql-hl";
          existingSecret = secretName;
        };

        serviceMonitor = { enabled = false; };
      };
    };
  };
}

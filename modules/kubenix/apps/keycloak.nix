{ lib
, kubenix
, homelab
, ...
}:

let
  app = "keycloak";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;
  domain = "identity.josevictor.me";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://registry-1.docker.io/cloudpirates/keycloak";
        chart = app;
        version = "0.14.2";
        sha256 = "sha256-wLz9gXImB232NqOhviNfxXREpXg3oKPMaTUFxPTvPBU=";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repository = "keycloak/keycloak";
          tag = "26.5.2";
        };

        # Disable embedded PostgreSQL - use external
        postgres = {
          enabled = false;
        };

        # External PostgreSQL configuration
        database = {
          type = "postgres";
          host = "postgresql-18-hl";
          port = "5432";
          name = "keycloak";
          existingSecret = secretName;
        };

        # Keycloak configuration
        keycloak = {
          hostname = domain;
          existingSecret = secretName;
          secretKeys = {
            adminPasswordKey = "KEYCLOAK_ADMIN_PASSWORD";
          };
        };

        # Resources for single instance (Java needs 1Gi+)
        resources = {
          requests = {
            cpu = "500m";
            memory = "1Gi";
          };
          limits = {
            cpu = "2000m";
            memory = "2Gi";
          };
        };

        # Health checks
        livenessProbe = {
          enabled = true;
          initialDelaySeconds = 60;
          periodSeconds = 30;
        };
        readinessProbe = {
          enabled = true;
          initialDelaySeconds = 30;
          periodSeconds = 10;
        };

        # Ingress configuration
        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          hosts = [
            {
              host = domain;
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
              hosts = [ domain ];
              secretName = "wildcard-tls";
            }
          ];
        };

        # Service configuration
        service = {
          type = "ClusterIP";
          port = 8080;
        };
      };
    };
  };
}

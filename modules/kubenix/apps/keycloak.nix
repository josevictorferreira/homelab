{
  lib,
  kubenix,
  homelab,
  ...
}:

let
  app = "keycloak";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;
  domain = "keycloak.${homelab.domain}";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://codecentric.github.io/helm-charts";
        chart = "keycloak";
        version = "18.10.0";
        sha256 = "sha256-keMWy0v8aG/8N2w5tjTheJ80ja1eUApAylMa/X35J2o=";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repository = "keycloak/keycloak";
          tag = "17.0.1";
        };

        # Disable embedded PostgreSQL - use external
        postgresql = {
          enabled = false;
        };

        # External PostgreSQL configuration
        database = {
          vendor = "postgres";
          host = "postgresql-18-hl";
          port = 5432;
          username = "postgres";
          password = "secret";
          database = "keycloak";
        };

        # Keycloak configuration
        keycloak = {
          hostname = domain;
          http = {
            port = 8080;
          };
          production = true;
        };

        # Resources for single instance
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

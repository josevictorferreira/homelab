{ kubenix, homelab, ... }:

let
  app = "synapse";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://ananace.gitlab.io/charts";
        chart = "matrix-synapse";
        version = "3.12.19";
        sha256 = "1ykzpi98qlwbixc34jfxx0xq3x0rmhbmv5xqvarbzjpkgi3fnlaf";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repository = "ghcr.io/element-hq/synapse";
          tag = "v1.146.0";
          pullPolicy = "IfNotPresent";
        };

        serverName = "josevictor.me";
        publicServerName = "matrix.josevictor.me";
        publicBaseurl = "https://matrix.josevictor.me/";

        config = {
          # Disable federation
          federation_domain_whitelist = [ ];
          federation_verify_certificates = false;

          # Registration settings - invite only
          enable_registration = true;
          registrations_require_3pid = [
            {
              medium = "email";
            }
          ];

          # Bridge configurations removed - to be added later when bridges are configured
          # app_service_config_files will be populated when bridges are added
        };

        # External PostgreSQL
        postgresql.enabled = false;
        externalPostgresql = {
          host = "postgresql-18-hl";
          port = 5432;
          username = "synapse";
          database = "synapse";
          existingSecret = secretName;
          existingSecretPasswordKey = "postgres-password";
        };

        # Ingress configuration
        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          includeServerName = false;
          csHosts = [ "matrix.josevictor.me" ];
          tls = [
            {
              hosts = [ "matrix.josevictor.me" ];
              secretName = "wildcard-tls";
            }
          ];
        };

        # Service configuration
        service = {
          type = "ClusterIP";
          port = 8008;
        };

        # Persistence for media store and state
        persistence = {
          enabled = true;
          storageClass = "rook-ceph-block";
          accessMode = "ReadWriteOnce";
          size = "20Gi";
          annotations = {
            "helm.sh/resource-policy" = "keep";
          };
        };

        # Resources
        resources = {
          requests = {
            cpu = "250m";
            memory = "512Mi";
          };
          limits = {
            cpu = "1000m";
            memory = "2Gi";
          };
        };

        # Disable well-known service (not needed without federation)
        wellknown.enabled = false;
      };
    };
  };
}

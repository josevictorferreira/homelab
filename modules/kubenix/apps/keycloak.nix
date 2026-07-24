{
  kubenix,
  homelab,
  ...
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
      inherit namespace;

      values = {
        global = {
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
        };

        image = {
          repository = "keycloak/keycloak";
          tag = "26.7.0@sha256:1362a9d9f13ab325231ea133610cc905e12805804abc7acbef552dd613720aa6";
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
          # Production mode: terminate TLS at ingress, trust X-Forwarded-* headers
          production = true;
          proxyHeaders = "xforwarded";
          hostnameStrict = false;
          httpEnabled = true;
        };

        # Resources for single instance (Java needs 1Gi+)
        resources = {
          requests = {
            cpu = "200m";
            memory = "512Mi";
          };
          limits = {
            cpu = "500m";
            memory = "1.5Gi";
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
          className = kubenix.lib.defaultIngressClass;
          annotations = {
            "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
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
              secretName = kubenix.lib.defaultTLSSecret;
            }
          ];
        };
        # Service configuration
        service = {
          type = "ClusterIP";
          port = 8080;
        };

        # Seed /opt/keycloak/providers emptyDir with base providers + Valoris theme jar.
        # Chart mounts keycloak-providers emptyDir at /opt/keycloak/providers in main
        # container, which hides base image providers. Two-step init restores them
        # and then overlays the Valoris theme jar.
        extraInitContainers = [
          {
            name = "copy-base-providers";
            image = "keycloak/keycloak:26.7.0@sha256:1362a9d9f13ab325231ea133610cc905e12805804abc7acbef552dd613720aa6";
            command = [
              "sh"
              "-c"
              "cp -r /opt/keycloak/providers/. /shared/"
            ];
            volumeMounts = [
              {
                name = "keycloak-providers";
                mountPath = "/shared";
              }
            ];
          }
          {
            name = "add-valoris-theme";
            image = "ghcr.io/josevictorferreira/valoris-identity:v0.5.0";
            command = [
              "sh"
              "-c"
              "cp /theme.jar /shared/valoris-theme.jar"
            ];
            volumeMounts = [
              {
                name = "keycloak-providers";
                mountPath = "/shared";
              }
            ];
          }
          {
            name = "add-oratoria-theme";
            image = "ghcr.io/josevictorferreira/oratoria-identity:v0.4.0";
            command = [
              "sh"
              "-c"
              "cp /theme.jar /shared/oratoria-theme.jar"
            ];
            volumeMounts = [
              {
                name = "keycloak-providers";
                mountPath = "/shared";
              }
            ];
          }
          {
            name = "add-homelab-theme";
            image = "ghcr.io/josevictorferreira/homelab-identity:v0.1.1";
            command = [
              "sh"
              "-c"
              "cp /theme.jar /shared/homelab-theme.jar"
            ];
            volumeMounts = [
              {
                name = "keycloak-providers";
                mountPath = "/shared";
              }
            ];
          }
        ];
      };
    };
  };
}

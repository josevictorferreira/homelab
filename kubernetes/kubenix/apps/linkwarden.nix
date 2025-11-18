{ lib
, kubenix
, homelab
, ...
}:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "linkwarden";
  bucketName = "linkwarden-files";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/fmjstudios/helm/linkwarden";
        chart = "linkwarden";
        version = "0.3.3";
        sha256 = "sha256-rFzutBrDDF4qVj38dYazjv3iUl2uszIJSKWPwrRdX1E=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        image = {
          registry = "ghcr.io";
          repository = "linkwarden/linkwarden";
          tag = "v2.13.0@sha256:bd3565d3f13c2d590f417710819f4c6b4fe19f8b841fc45ab3fe4c61ba12d34f";
        };

        linkwarden = {
          replicas = 1;

          labels = {
            app = app;
            release = app;
          };
          domain = kubenix.lib.domainFor app;

          data = {
            storageType = "s3";
            s3 = {
              bucketName = bucketName;
              endpoint = "http://rook-ceph-rgw-ceph-objectstore.${homelab.kubernetes.namespaces.storage}.svc.cluster.local";
              region = "us-east-1";
              existingSecret = "linkwarden-s3";
            };
            filesystem.pvc.existingClaim = "true";
          };

          database = {
            existingSecret = "linkwarden-db";
          };
        };

        resources = {
          requests = {
            cpu = "50m";
            memory = "512Mi";
          };
          limits.memory = "2.5Gi";
        };

        service = {
          type = "LoadBalancer";
          port = 80;
        };

        postgresql.enabled = false;

        ingress = kubenix.lib.ingressDomainForService app;
      };
    };

    resources = {
      services.linkwarden = {
        metadata = {
          namespace = namespace;
          annotations = kubenix.lib.serviceAnnotationFor app;
        };
      };

      configMaps."postgres-linkwarden-dashboard" = {
        metadata = {
          namespace = homelab.kubernetes.namespaces.monitoring;
          labels.grafana_dashboard = "1";
        };
        data = {
          "postgres-linkwarden-dashboard.json" = builtins.toJSON {
            id = null;
            uid = "postgres-linkwarden";
            title = "Postgres - Linkwarden";
            tags = [
              "postgres"
              "linkwarden"
            ];
            timezone = homelab.timeZone;
            schemaVersion = 17;
            version = 1;
            refresh = "10s";

            panels = [
              {
                type = "timeseries";
                title = "Connections";
                datasource = {
                  type = "postgres";
                  uid = "postgres-database-linkwarden";
                };
                targets = [
                  {
                    refId = "A";
                    rawSql = ''
                      SELECT
                        now() AS time,
                        numbackends AS "connections"
                      FROM pg_stat_database
                      WHERE datname = 'linkwarden';
                    '';
                    format = "time_series";
                  }
                ];
              }
            ];
          };
        };
      };

      deployments.linkwarden = {
        metadata.namespace = namespace;
        spec.template.spec.containers.linkwarden = {
          env = [
            {
              name = "SPACES_KEY";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "linkwarden-s3";
                key = lib.mkForce "AWS_ACCESS_KEY_ID";
              };
            }
            {
              name = "SPACES_SECRET";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "linkwarden-s3";
                key = lib.mkForce "AWS_SECRET_ACCESS_KEY";
              };
            }
            {
              name = "OPENROUTER_MODEL";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "openrouter-secrets";
                key = lib.mkForce "OPENROUTER_MODEL";
              };
            }
            {
              name = "OPENROUTER_API_KEY";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "openrouter-secrets";
                key = lib.mkForce "OPENROUTER_API_KEY";
              };
            }
            {
              name = "SPACES_FORCE_PATH_STYLE";
              value = "true";
            }
          ];
          envFrom = [
            {
              secretRef.name = "linkwarden-secrets";
            }
          ];
        };
      };

      objectbucketclaim."linkwarden-s3" = {
        metadata = {
          namespace = namespace;
        };
        spec = {
          bucketName = bucketName;
          storageClassName = "rook-ceph-objectstore";
        };
      };
    };

  };
}

{ kubenix, homelab, ... }:

let
  app = "synapse";
  secretName = "${app}-env";
  namespace = homelab.kubernetes.namespaces.applications;

  # mautrix-discord is enabled - secrets exist in k8s-secrets.enc.yaml
  enableDiscord = true;

  # mautrix-slack is enabled - secrets exist in k8s-secrets.enc.yaml
  enableSlack = true;
  bucketName = "matrix-synapse-media";
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
      noHooks = true; # Disable hooks to skip test pod (exceeds CPU quota)
      inherit namespace;

      values = {
        image = {
          repository = "ghcr.io/element-hq/synapse";
          tag = "v1.146.0";
          pullPolicy = "IfNotPresent";
        };

        # Deployment strategy - must be Recreate for RWO PVCs
        # RollingUpdate causes Multi-Attach errors since the PVC can only
        # be mounted to one pod at a time
        synapse = {
          strategy = {
            type = "Recreate";
            rollingUpdate = null;
          };
          # Increase startup probe - Synapse takes >2 min to start with bridges
          startupProbe = {
            failureThreshold = 30; # 5 minutes (30 * 10s period)
          };

          # S3 storage provider: runtime pip install + AWS config
          extraCommands = [
            "mkdir -p /modules"
            "echo '[default]' > /modules/aws-config"
            "echo 's3 =' >> /modules/aws-config"
            "echo '  addressing_style = path' >> /modules/aws-config"
            "pip install --no-cache-dir --target /modules boto3 psycopg2-binary"
            "pip install --no-cache-dir --target /modules --no-deps synapse-s3-storage-provider"
          ];

          extraVolumes = [
            {
              name = "synapse-python-modules";
              emptyDir = { };
            }
            {
              name = "mautrix-whatsapp-registration";
              secret = {
                secretName = "mautrix-whatsapp-registration";
                items = [
                  {
                    key = "registration.yaml";
                    path = "mautrix-whatsapp-registration.yaml";
                  }
                ];
              };
            }
          ]
          ++ (
            if enableDiscord then
              [
                {
                  name = "mautrix-discord-registration";
                  secret = {
                    secretName = "mautrix-discord-registration";
                    items = [
                      {
                        key = "registration.yaml";
                        path = "mautrix-discord-registration.yaml";
                      }
                    ];
                  };
                }
              ]
            else
              [ ]
          )
          ++ (
            if enableSlack then
              [
                {
                  name = "mautrix-slack-registration";
                  secret = {
                    secretName = "mautrix-slack-registration";
                    items = [
                      {
                        key = "registration.yaml";
                        path = "mautrix-slack-registration.yaml";
                      }
                    ];
                  };
                }
              ]
            else
              [ ]
          );

          extraVolumeMounts = [
            {
              name = "synapse-python-modules";
              mountPath = "/modules";
            }
            {
              name = "mautrix-whatsapp-registration";
              mountPath = "/synapse/config/conf.d/mautrix-whatsapp-registration.yaml";
              subPath = "mautrix-whatsapp-registration.yaml";
              readOnly = true;
            }
          ]
          ++ (
            if enableDiscord then
              [
                {
                  name = "mautrix-discord-registration";
                  mountPath = "/synapse/config/conf.d/mautrix-discord-registration.yaml";
                  subPath = "mautrix-discord-registration.yaml";
                  readOnly = true;
                }
              ]
            else
              [ ]
          )
          ++ (
            if enableSlack then
              [
                {
                  name = "mautrix-slack-registration";
                  mountPath = "/synapse/config/conf.d/mautrix-slack-registration.yaml";
                  subPath = "mautrix-slack-registration.yaml";
                  readOnly = true;
                }
              ]
            else
              [ ]
          );

          extraEnv = [
            {
              name = "PYTHONPATH";
              value = "/modules";
            }
            {
              name = "AWS_CONFIG_FILE";
              value = "/modules/aws-config";
            }
            {
              name = "AWS_EC2_METADATA_DISABLED";
              value = "true";
            }
            {
              name = "AWS_ACCESS_KEY_ID";
              valueFrom = {
                secretKeyRef = {
                  name = bucketName;
                  key = "AWS_ACCESS_KEY_ID";
                };
              };
            }
            {
              name = "AWS_SECRET_ACCESS_KEY";
              valueFrom = {
                secretKeyRef = {
                  name = bucketName;
                  key = "AWS_SECRET_ACCESS_KEY";
                };
              };
            }
          ];
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

          # Bridge configurations
          # app_service_config_files will be populated when bridges are added
        };

        extraConfig = {
          app_service_config_files = [
            "/synapse/config/conf.d/mautrix-whatsapp-registration.yaml"
          ]
          ++ (if enableDiscord then [ "/synapse/config/conf.d/mautrix-discord-registration.yaml" ] else [ ])
          ++ (if enableSlack then [ "/synapse/config/conf.d/mautrix-slack-registration.yaml" ] else [ ]);

          # S3 storage provider for media
          media_storage_providers = [
            {
              module = "s3_storage_provider.S3StorageProviderBackend";
              store_local = true;
              store_remote = true;
              store_synchronous = false;
              config = {
                bucket = bucketName;
                endpoint_url = kubenix.lib.objectStoreEndpoint;
                region_name = "us-east-1";
                prefix = "synapse/";
                request_checksum_calculation = "when_required";
                response_checksum_validation = "when_required";
              };
            }
          ];

          # Rate limiting exemptions for appservices (bridges)
          # Prevents 429 errors when bridges sync many rooms at once
          rc_joins = {
            local = {
              per_second = 50;
              burst_count = 100;
            };
            remote = {
              per_second = 10;
              burst_count = 20;
            };
          };

          rc_joins_per_room = {
            per_second = 50;
            burst_count = 100;
          };

          rc_message = {
            per_second = 50;
            burst_count = 100;
          };

          rc_invites = {
            per_room = {
              per_second = 50;
              burst_count = 100;
            };
            per_user = {
              per_second = 50;
              burst_count = 100;
            };
            per_issuer = {
              per_second = 50;
              burst_count = 100;
            };
          };

          # Exempt appservice user from rate limits
          rc_admin_redaction = {
            per_second = 100;
            burst_count = 200;
          };
        };

        # External PostgreSQL (use postgres superuser)
        postgresql.enabled = false;
        externalPostgresql = {
          host = "postgresql-18-hl";
          port = 5432;
          username = "postgres";
          database = "synapse";
          existingSecret = secretName;
          existingSecretPasswordKey = "postgres-password";
        };

        # Use existing cluster Redis
        redis.enabled = false;
        existingSecret = secretName;
        externalRedis = {
          host = "redis-headless";
          port = 6379;
          existingSecret = "redis-auth";
          existingSecretPasswordKey = "redis-password";
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

        # Disable test hooks - they exceed namespace CPU quota
        tests.enabled = false;
      };
    };
    resources = {
      objectbucketclaim."matrix-synapse-media" = {
        metadata = {
          inherit namespace;
        };
        spec = {
          inherit bucketName;
          storageClassName = "rook-ceph-objectstore";
        };
      };
    };
  };
}

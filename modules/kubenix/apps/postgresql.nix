{ lib
, kubenix
, homelab
, ...
}:

let
  image = {
    registry = "ghcr.io";
    repository = "josevictorferreira/postgresql-vchord-bitnami";
    tag = "54c9cd376be1eb5a2b3baf4df0f4dc86c472325c";
  };
  namespace = homelab.kubernetes.namespaces.applications;
  bootstrapDatabases = homelab.kubernetes.databases.postgres;
  mkCreateDb = db: ''
    		psql -h postgresql -U postgres -c 'ALTER SYSTEM SET shared_preload_libraries = "vchord.so"'
        echo "Ensuring database '${db}' exists..."
        psql -h postgresql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 \
          || psql -h postgresql -U postgres -d postgres -c "CREATE DATABASE \"${db}\";"

        echo "Installing pgvecto.rs extension in database '${db}'..."
        psql -h postgresql -U postgres -d ${db} -c "DROP EXTENSION IF EXISTS vectors;CREATE EXTENSION IF NOT EXISTS vchord CASCADE;" || echo "Extension installation completed for ${db}"
  '';
  createDbCommands = lib.concatStringsSep "\n" (map mkCreateDb bootstrapDatabases);
  configChecksum = builtins.hashString "sha256" createDbCommands;
  jobName = "postgresql-bootstrap-${builtins.substring 0 8 configChecksum}";
in
{
  kubernetes = {
    helm.releases."postgresql" = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://registry-1.docker.io/bitnamicharts/postgresql";
        chart = "postgresql";
        version = "16.7.27";
        sha256 = "sha256-Sl3CjRqPSVl5j8BYNvahUiAZqCUIAK3Xsv/bMFdQ3t8=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        image = image;

        postgresqlSharedPreloadLibraries = "vchord.so";

        global.security.allowInsecureImages = true;

        global.postgresql.auth = {
          database = "linkwarden";
          existingSecret = "postgresql-auth";
          secretKeys = {
            adminPasswordKey = "admin-password";
            userPasswordKey = "user-password";
            replicationPasswordKey = "replication-password";
          };
        };

        primary.persistence = {
          enabled = true;
          storageClass = "rook-ceph-block";
          reclaimPolicy = "Retain";
          accessModes = [ "ReadWriteOnce" ];
        };
        primary.service = kubenix.lib.plainServiceFor "postgresql";
        primary.initdb.args = "--data-checksums";
        primary.extendedConfiguration = ''
          shared_preload_libraries = 'vchord.so'
          search_path = '"$user", public, vectors'
          logging_collector = on
          max_wal_size = 2GB
          min_wal_size = '512MB'
          shared_buffers = 512MB
          wal_buffers = '32MB'
          wal_compression = on
          wal_keep_size = '512MB'
          checkpoint_timeout = '30min'
          checkpoint_completion_target = 0.9
          effective_cache_size = '10GB'
          work_mem = '64MB'
          maintenance_work_mem = '2GB'
          synchronous_commit = off
          autovacuum_max_workers = 5
          autovacuum_naptime = '10s'
          autovacuum_vacuum_cost_delay = '10ms'
          autovacuum_vacuum_cost_limit = 2000
          log_min_duration_statement = 2000
          log_checkpoints = on
        '';
        primary.resources = {
          limits = {
            cpu = "150m";
            memory = "1Gi";
            ephemeral-storage = "1Gi";
          };
          requests = {
            cpu = "50m";
            memory = "128Mi";
            ephemeral-storage = "50Mi";
          };
        };
      };
    };

    resources.configMaps."postgresql-bootstrap" = {
      metadata = {
        name = "postgresql-bootstrap";
        namespace = namespace;
      };
      data = {
        databases = createDbCommands;
      };
    };

    resources.jobs."${jobName}" = {
      metadata = {
        name = jobName;
        namespace = namespace;
      };
      spec.template = {
        metadata.annotations."checksum/config" = configChecksum;
        spec = {
          restartPolicy = "OnFailure";
          containers = [
            {
              name = "psql";
              image = "${image.registry}/${image.repository}:${image.tag}";
              env = [
                {
                  name = "PGPASSWORD";
                  valueFrom.secretKeyRef = {
                    name = "postgresql-auth";
                    key = "admin-password";
                  };
                }
              ];
              command = [
                "sh"
                "-c"
              ];
              args = [
                ''
                  set -e
                  ${createDbCommands}
                ''
              ];
            }
          ];
        };
      };
    };

  };
}

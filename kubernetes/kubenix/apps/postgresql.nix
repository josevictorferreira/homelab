{ lib, kubenix, homelab, ... }:

let
  image = {
    registry = "ghcr.io";
    repository = "josevictorferreira/postgresql-vchord-bitnami";
    tag = "f78dc50630f71c248a3b71e59e2bd9e8d63242a3";
  };
  namespace = homelab.kubernetes.namespaces.applications;
  bootstrapDatabases = homelab.kubernetes.databases.postgres;
  mkCreateDb = db: ''
		psql -h postgresql -U postgres -c 'ALTER SYSTEM SET shared_preload_libraries = "vectors.so"'
		psql -h postgresql -U postgres -c 'ALTER SYSTEM SET search_path TO "$user", public, vectors'
    echo "Ensuring database '${db}' exists..."
    psql -h postgresql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 \
      || psql -h postgresql -U postgres -d postgres -c "CREATE DATABASE \"${db}\";"

    echo "Installing pgvecto.rs extension in database '${db}'..."
    psql -h postgresql -U postgres -d ${db} -c "DROP EXTENSION IF EXISTS vectors;CREATE EXTENSION IF NOT EXISTS vectors;" || echo "Extension installation completed for ${db}"
  '';
  createDbCommands = lib.concatStringsSep "\n" (map mkCreateDb bootstrapDatabases);
  configChecksum = builtins.hashString "sha256" createDbCommands;
  jobName = "postgresql-bootstrap-${builtins.substring 0 8 configChecksum}";
in
{
  kubernetes = {
    helm.releases."postgresql" =
    {
      chart = kubenix.lib.helm.fetch
        {
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
              command = [ "sh" "-c" ];
              args = [''
                set -e
                ${createDbCommands}
              ''];
            }
          ];
        };
      };
    };

  };
}

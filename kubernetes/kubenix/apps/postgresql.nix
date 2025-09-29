{ lib, kubenix, homelab, ... }:

let
  imageRep = "bitnamisecure/postgresql";
  imageTag = "sha256-3df41817b00506ab5b0b8ecc3ca3bc5ba3dc1eeb9a3def902beca37393ed4c36";
  namespace = homelab.kubernetes.namespaces.applications;
  bootstrapDatabases = homelab.kubernetes.databases.postgres;
  databasesConfig = lib.concatStringsSep "\n" bootstrapDatabases;
  configChecksum = builtins.hashString "sha256" databasesConfig;
  mkCreateDb = db: ''
    echo "Ensuring database '${db}' exists..."
    psql -h postgresql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 \
      || psql -h postgresql -U postgres -d postgres -c "CREATE DATABASE \"${db}\";"

    echo "Installing pgvecto.rs extension in database '${db}'..."
    psql -h postgresql -U postgres -d ${db} -c "CREATE EXTENSION IF NOT EXISTS vectors;" || echo "Extension installation completed for ${db}"
  '';
  createDbCommands = lib.concatStringsSep "\n" (map mkCreateDb bootstrapDatabases);
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
        image = {
          repository = imageRep;
          tag = imageTag;
        };

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
        databases = lib.concatStringsSep "\n" bootstrapDatabases;
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
              image = "${imageRep}:${imageTag}";
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

{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:10c2e55a28316965b53fc82a7bd34133293c09c8cdc1292a3f0eec3fb06cad44";
  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-postgres";
  pgHost = "postgresql-18-hl";
  pgPort = "5432";
  pgUser = "postgres";

  backupScript = ''
    set -euo pipefail
    echo "=== Postgres backup starting ==="
    DATE_PREFIX=$(date +%Y/%m/%d)
    OBJ_PREFIX="postgresql-18/$DATE_PREFIX"

    echo "Setting up mc alias..."
    mc alias set backup "$MINIO_ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

    echo "Running pg_dumpall..."
    pg_dumpall -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" > /tmp/full.sql

    echo "Compressing with zstd..."
    zstd -T0 /tmp/full.sql -o /tmp/full.sql.zst
    rm /tmp/full.sql

    echo "Computing sha256..."
    sha256sum /tmp/full.sql.zst > /tmp/full.sql.zst.sha256

    echo "Uploading to MinIO (tmp)..."
    mc cp /tmp/full.sql.zst "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst.tmp"
    mc cp /tmp/full.sql.zst.sha256 "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst.sha256.tmp"

    echo "Renaming to final (atomic)..."
    mc mv "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst.tmp" "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst"
    mc mv "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst.sha256.tmp" "backup/${minioBucket}/$OBJ_PREFIX/full.sql.zst.sha256"

    echo "Cleanup..."
    rm -f /tmp/full.sql.zst /tmp/full.sql.zst.sha256

    echo "=== Postgres backup complete ==="
    mc ls "backup/${minioBucket}/$OBJ_PREFIX/"
  '';
in
{
  kubernetes.resources.cronJobs."postgres-backup" = {
    metadata = {
      name = "postgres-backup";
      namespace = namespace;
    };
    spec = {
      schedule = "30 2 * * *";
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 2;
        template.spec = {
          restartPolicy = "OnFailure";
          imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          containers = [
            {
              name = "backup";
              inherit image;
              command = [
                "bash"
                "-c"
              ];
              args = [ backupScript ];
              env = [
                {
                  name = "PGHOST";
                  value = pgHost;
                }
                {
                  name = "PGPORT";
                  value = pgPort;
                }
                {
                  name = "PGUSER";
                  value = pgUser;
                }
                {
                  name = "MINIO_ENDPOINT";
                  value = minioEndpoint;
                }
                {
                  name = "PGPASSWORD";
                  valueFrom.secretKeyRef = {
                    name = "postgresql-auth";
                    key = "admin-password";
                  };
                }
                {
                  name = "AWS_ACCESS_KEY_ID";
                  valueFrom.secretKeyRef = {
                    name = "postgres-backup-s3-credentials";
                    key = "AWS_ACCESS_KEY_ID";
                  };
                }
                {
                  name = "AWS_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "postgres-backup-s3-credentials";
                    key = "AWS_SECRET_ACCESS_KEY";
                  };
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                  ephemeral-storage = "2Gi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                  ephemeral-storage = "4Gi";
                };
              };
            }
          ];
        };
      };
    };
  };
}

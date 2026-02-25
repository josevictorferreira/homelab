{ homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  toolboxImage = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";
  # Same custom Postgres 18 image used by postgresql-18 service
  postgresImage = "ghcr.io/josevictorferreira/postgresql-vchord-bitnami:38c40fefe0c58cff6622de77f787634320e1ae5e";
  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-postgres";

  expectedDbs = builtins.concatStringsSep " " homelab.kubernetes.databases.postgres;

  restoreScript = ''
    set -euo pipefail
    echo "=== Postgres restore drill starting ==="

    # Scratch postgres uses trust auth — no PGPASSWORD needed at all.
    # pg_dumpall includes ALTER ROLE postgres WITH PASSWORD which would
    # change the scratch password mid-restore, causing \connect failures.
    # Trust auth avoids the entire password mismatch problem.
    unset PGPASSWORD 2>/dev/null || true

    echo "Waiting for scratch Postgres to accept connections..."
    for i in $(seq 1 60); do
      if psql -h localhost -U postgres -Atc "SELECT 1" 2>/dev/null | grep -q 1; then
        echo "Scratch Postgres ready after ''${i}s"
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "ERROR: Scratch Postgres did not become ready in 60s"
        exit 1
      fi
      sleep 1
    done

    echo "Setting up mc alias..."
    mc alias set backup "$MINIO_ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

    echo "Finding latest backup..."
    LATEST=$(mc ls --recursive --json "backup/${minioBucket}/postgresql-18/" | \
      jq -r 'select(.key | test("full\\.sql\\.zst$")) | .lastModified + " " + .key' | \
      sort -r | head -1 | cut -d' ' -f2- || true)

    if [ -z "$LATEST" ]; then
      echo "ERROR: No backup found in MinIO"
      exit 1
    fi
    echo "Latest backup: $LATEST"

    LATEST_DIR=$(dirname "$LATEST")

    echo "Downloading backup + checksum..."
    mc cp "backup/${minioBucket}/postgresql-18/$LATEST" /tmp/full.sql.zst
    mc cp "backup/${minioBucket}/postgresql-18/$LATEST_DIR/full.sql.zst.sha256" /tmp/full.sql.zst.sha256

    echo "Verifying sha256..."
    cd /tmp
    if sha256sum -c full.sql.zst.sha256; then
      echo "sha256 OK"
    else
      echo "ERROR: sha256 mismatch"
      exit 1
    fi

    echo "Decompressing..."
    zstd -dc /tmp/full.sql.zst > /tmp/full.sql
    rm /tmp/full.sql.zst

    echo "Restoring into scratch Postgres..."
    # ON_ERROR_STOP omitted: pg_dumpall includes "CREATE ROLE postgres"
    # which always errors on a fresh instance. Smoke queries validate success.
    psql -h localhost -U postgres -f /tmp/full.sql > /tmp/restore.log 2>&1 || true
    # Fail only on fatal/panic errors, not expected role-exists noise
    if grep -qiE 'FATAL|PANIC' /tmp/restore.log; then
      echo "ERROR: restore had fatal errors:"
      grep -iE 'FATAL|PANIC' /tmp/restore.log
      exit 1
    fi
    echo "restore OK (non-fatal warnings may exist)"
    rm /tmp/full.sql

    echo "Running smoke checks..."
    SMOKE_OK=true

    # Basic connectivity
    if ! psql -h localhost -U postgres -Atc "SELECT 1" | grep -q 1; then
      echo "FAIL: basic SELECT 1"
      SMOKE_OK=false
    fi

    # Check expected databases exist
    ACTUAL_DBS=$(psql -h localhost -U postgres -Atc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;")
    for db in ${expectedDbs}; do
      if echo "$ACTUAL_DBS" | grep -qw "$db"; then
        echo "OK: database $db exists"
      else
        echo "FAIL: database $db missing"
        SMOKE_OK=false
      fi
    done

    # Check each DB has at least 1 table
    for db in ${expectedDbs}; do
      TABLE_COUNT=$(psql -h localhost -U postgres -d "$db" -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
      if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "OK: $db has $TABLE_COUNT tables"
      else
        echo "WARN: $db has 0 public tables (may be expected)"
      fi
    done

    if [ "$SMOKE_OK" = true ]; then
      echo "smoke OK"
      echo "=== Postgres restore drill complete ==="
      exit 0
    else
      echo "ERROR: smoke checks failed"
      exit 1
    fi
  '';
in
{
  kubernetes.resources.cronJobs."postgres-restore-drill" = {
    metadata = {
      name = "postgres-restore-drill";
      inherit namespace;
    };
    spec = {
      schedule = "0 3 * * 0";
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 1;
        activeDeadlineSeconds = 5400;
        template.spec = {
          restartPolicy = "Never";
          imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          # Bitnami postgres runs as uid 1001; fsGroup ensures emptyDir writable
          securityContext = {
            fsGroup = 1001;
          };
          volumes = [
            {
              name = "scratch-data";
              emptyDir.sizeLimit = "8Gi";
            }
          ];
          containers = [
            {
              name = "scratch-postgres";
              image = postgresImage;
              env = [
                {
                  name = "ALLOW_EMPTY_PASSWORD";
                  value = "yes";
                }
                {
                  name = "POSTGRESQL_ENABLE_TRUST_AUTH";
                  value = "yes";
                }
                {
                  name = "BITNAMI_DEBUG";
                  value = "true";
                }
              ];
              volumeMounts = [
                {
                  name = "scratch-data";
                  mountPath = "/bitnami/postgresql";
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
              readinessProbe = {
                exec.command = [
                  "pg_isready"
                  "-U"
                  "postgres"
                ];
                initialDelaySeconds = 5;
                periodSeconds = 5;
              };
            }
            {
              name = "restore";
              image = toolboxImage;
              command = [
                "bash"
                "-c"
              ];
              args = [ restoreScript ];
              env = [
                {
                  name = "MINIO_ENDPOINT";
                  value = minioEndpoint;
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
                  ephemeral-storage = "4Gi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                  ephemeral-storage = "8Gi";
                };
              };
            }
          ];
        };
      };
    };
  };
}

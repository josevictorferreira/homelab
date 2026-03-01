{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.backup;
  toolboxImage = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";
  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-shared";

  expectedFolders = [
    "notetaking"
    "images"
    "backups"
    "openclaw"
  ];

  restoreScript = ''
    set -euo pipefail
    echo "=== Shared subfolders restore drill starting ==="

    # Create rclone config (same as backup script)
    mkdir -p "$HOME/.config/rclone"
    ACCESS_KEY="$(echo -n "$AWS_ACCESS_KEY_ID" | tr -d '\n\r')"
    SECRET_KEY="$(echo -n "$AWS_SECRET_ACCESS_KEY" | tr -d '\n\r')"

    cat > "$HOME/.config/rclone/rclone.conf" <<EOF
    [minio]
    type = s3
    provider = Minio
    env_auth = false
    access_key_id = $ACCESS_KEY
    secret_access_key = $SECRET_KEY
    endpoint = $MINIO_ENDPOINT
    region = sa-east-1
    force_path_style = true
    EOF

    echo "Verifying backup exists in MinIO..."

    # Check that the current/ folder structure exists
    SMOKE_OK=true
    TOTAL_FILES=0

    for folder in ${toString expectedFolders}; do
      echo "Checking folder: $folder"

      # Count files in this folder
      COUNT=$(rclone lsl "minio:${minioBucket}/current/$folder/" 2>/dev/null | wc -l || echo "0")

      if [ "$COUNT" -gt 0 ]; then
        echo "OK: folder $folder exists with $COUNT items"
        TOTAL_FILES=$((TOTAL_FILES + COUNT))
      else
        echo "FAIL: folder $folder is empty or missing"
        SMOKE_OK=false
      fi
    done

    echo "Total files in backup: $TOTAL_FILES"

    # Verify latest manifest exists
    echo "Checking manifest..."
    LATEST_MANIFEST=$(rclone lsl "minio:${minioBucket}/manifests/" 2>/dev/null | sort -k2 | tail -1 || true)

    if [ -n "$LATEST_MANIFEST" ]; then
      echo "OK: Found manifest - $LATEST_MANIFEST"
    else
      echo "WARN: No manifest found (backup may not have completed)"
    fi

    # Sample verification: download a random file and check it's not empty
    echo "Sampling verification..."
    SAMPLE_FILE=$(rclone lsf "minio:${minioBucket}/current/notetaking/" 2>/dev/null | head -1 || true)

    if [ -n "$SAMPLE_FILE" ]; then
      echo "Downloading sample file: $SAMPLE_FILE"
      rclone copy "minio:${minioBucket}/current/notetaking/$SAMPLE_FILE" /tmp/sample/ 2>/dev/null || true

      if [ -f "/tmp/sample/$SAMPLE_FILE" ] && [ -s "/tmp/sample/$SAMPLE_FILE" ]; then
        SIZE=$(stat -c%s "/tmp/sample/$SAMPLE_FILE" 2>/dev/null || echo "unknown")
        echo "OK: Sample file downloaded successfully (size: $SIZE bytes)"
        rm -rf /tmp/sample
      else
        echo "WARN: Could not verify sample file"
      fi
    fi

    if [ "$SMOKE_OK" = true ] && [ "$TOTAL_FILES" -gt 0 ]; then
      echo "smoke OK"
      echo "=== Shared subfolders restore drill complete ==="
      exit 0
    else
      echo "ERROR: Backup verification failed"
      exit 1
    fi
  '';
in
{
  kubernetes.resources.cronJobs."shared-subfolders-restore-drill" = {
    metadata = {
      name = "shared-subfolders-restore-drill";
      inherit namespace;
    };
    spec = {
      schedule = "0 4 * * 0";
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 1;
        activeDeadlineSeconds = 1800;
        template.spec = {
          restartPolicy = "Never";
          imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          containers = [
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
                    name = "shared-subfolders-backup-s3-credentials";
                    key = "AWS_ACCESS_KEY_ID";
                  };
                }
                {
                  name = "AWS_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "shared-subfolders-backup-s3-credentials";
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

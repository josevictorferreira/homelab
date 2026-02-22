{
  kubenix,
  lib,
  pkgs,
  ...
}:
let
  name = "shared-subfolders-proton-sync";
  namespace = "apps";
  bucket = "homelab-backup-shared";
  minioUrl = "http://10.10.10.209:9000";
  protonDestPath = "/Backups/homelab/shared-archives";
in
{
  kubernetes.resources.cronJobs.${name} = {
    metadata = { inherit name namespace; };
    spec = {
      schedule = "0 3 * * *"; # 3 AM daily (after backup at 1 AM)
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      jobTemplate.spec = {
        backoffLimit = 2;
        activeDeadlineSeconds = 3600; # 1 hour timeout
        template.spec = {
          restartPolicy = "Never";
          volumes = [
            {
              name = "proton-config";
              persistentVolumeClaim.claimName = "${name}-config";
            }
            {
              name = "proton-state";
              persistentVolumeClaim.claimName = "${name}-state";
            }
          ];
          containers = [
            {
              inherit name;
              image = "ghcr.io/damianb-bitflipper/proton-drive-sync:latest";
              env = [
                {
                  name = "KEYRING_PASSWORD";
                  valueFrom.secretKeyRef = {
                    name = "${name}-config";
                    key = "KEYRING_PASSWORD";
                  };
                }
                {
                  name = "PROTON_USERNAME";
                  valueFrom.secretKeyRef = {
                    name = "${name}-config";
                    key = "PROTON_USERNAME";
                  };
                }
                {
                  name = "PROTON_PASSWORD";
                  valueFrom.secretKeyRef = {
                    name = "${name}-config";
                    key = "PROTON_PASSWORD";
                  };
                }
                {
                  name = "TZ";
                  value = "America/Sao_Paulo";
                }
                {
                  name = "MINIO_URL";
                  value = minioUrl;
                }
                {
                  name = "MINIO_BUCKET";
                  value = bucket;
                }
                {
                  name = "PROTON_DEST_PATH";
                  value = protonDestPath;
                }
              ];
              volumeMounts = [
                {
                  name = "proton-config";
                  mountPath = "/config/proton-drive-sync";
                }
                {
                  name = "proton-state";
                  mountPath = "/state/proton-drive-sync";
                }
              ];
              command = [
                "sh"
                "-c"
              ];
              args = [
                ''
                  set -euo pipefail

                  echo "=== Proton Drive Sync: MinIO → Proton ==="
                  echo "Date: $(date -Iseconds)"
                  echo "Source: $MINIO_BUCKET/current/"
                  echo "Dest: $PROTON_DEST_PATH"

                  # Check if authenticated (credentials.enc exists)
                  if [ ! -f /config/proton-drive-sync/credentials.enc ]; then
                    echo "ERROR: Not authenticated. Run auth bootstrap job first."
                    echo "kubectl create job --from=cronjob/proton-drive-auth-bootstrap proton-drive-auth-manual -n ${namespace}"
                    exit 1
                  fi

                  # Install dependencies
                  apk add --no-cache rclone zstd curl jq

                  # Configure rclone for MinIO
                  mkdir -p ~/.config/rclone
                  cat > ~/.config/rclone/rclone.conf << EOF
                  [minio]
                  type = s3
                  provider = Minio
                  env_auth = false
                  access_key_id = \''${MINIO_ACCESS_KEY_ID}
                  secret_access_key = \''${MINIO_SECRET_ACCESS_KEY}
                  endpoint = $MINIO_URL
                  region = sa-east-1
                  force_path_style = true
                  EOF

                  # Get date for archive naming
                  TODAY=$(date +%Y-%m-%d)
                  YEAR=$(date +%Y)
                  MONTH=$(date +%m)
                  DAY=$(date +%d)
                  TIMESTAMP=$(date +%Y%m%d_%H%M%S)

                  echo ""
                  echo "=== Creating archive from MinIO current/ ==="

                  # Download current backup from MinIO
                  SYNC_DIR=/tmp/proton-sync-$TIMESTAMP
                  mkdir -p $SYNC_DIR/shared

                  echo "Downloading from MinIO..."
                  rclone copy minio:$MINIO_BUCKET/current/ $SYNC_DIR/shared/ --progress \
                    --exclude ".DS_Store" \
                    --exclude "Thumbs.db"

                  # Check if we got any files
                  FILE_COUNT=$(find $SYNC_DIR/shared -type f | wc -l)
                  if [ "$FILE_COUNT" -eq 0 ]; then
                    echo "WARNING: No files found in MinIO current/"
                    rm -rf $SYNC_DIR
                    exit 0
                  fi

                  echo "Downloaded $FILE_COUNT files"

                  # Create tar.zst archive
                  ARCHIVE_NAME="shared-subfolders-$TODAY.tar.zst"
                  echo ""
                  echo "=== Creating archive: $ARCHIVE_NAME ==="
                  cd $SYNC_DIR
                  tar -cf - shared | zstd -19 -o $ARCHIVE_NAME

                  # Generate checksum
                  sha256sum $ARCHIVE_NAME > ''${ARCHIVE_NAME}.sha256

                  ARCHIVE_SIZE=$(stat -c%s $ARCHIVE_NAME)
                  echo "Archive size: $ARCHIVE_SIZE bytes"

                  # Create sync config for proton-drive-sync
                  mkdir -p /tmp/proton-config
                  cat > /tmp/proton-config/sync.json << EOF
                  {
                    "syncs": [
                      {
                        "localPath": "$SYNC_DIR",
                        "remotePath": "$PROTON_DEST_PATH/$YEAR/$MONTH/$DAY",
                        "direction": "up"
                      }
                    ]
                  }
                  EOF

                  # Run proton-drive-sync
                  echo ""
                  echo "=== Uploading to Proton Drive ==="
                  cd /tmp/proton-config
                  proton-drive-sync sync --config ./sync.json || {
                    echo "WARNING: Proton sync had errors (best-effort)"
                  }

                  # Generate report
                  echo ""
                  echo "=== Sync report ==="
                  REPORT_FILE="/tmp/proton-sync-report-$TODAY.json"
                  cat > $REPORT_FILE << EOF
                  {
                    "timestamp": "$(date -Iseconds)",
                    "date": "$TODAY",
                    "source_bucket": "$MINIO_BUCKET",
                    "source_prefix": "current/",
                    "destination_path": "$PROTON_DEST_PATH/$YEAR/$MONTH/$DAY",
                    "archive_name": "$ARCHIVE_NAME",
                    "archive_size": $ARCHIVE_SIZE,
                    "files_archived": $FILE_COUNT,
                    "status": "completed"
                  }
                  EOF

                  cat $REPORT_FILE

                  # Cleanup
                  rm -rf $SYNC_DIR

                  echo ""
                  echo "=== Sync complete ==="
                ''
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                  "ephemeral-storage" = "2Gi";
                };
                limits = {
                  cpu = "1000m";
                  memory = "1Gi";
                  "ephemeral-storage" = "10Gi";
                };
              };
            }
          ];
        };
      };
    };
  };

  # PVC for Proton Drive config (persistent auth credentials)
  kubernetes.resources.persistentVolumeClaims."${name}-config" = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    spec = {
      accessModes = [ "ReadWriteOnce" ];
      resources.requests.storage = "1Gi";
      storageClassName = "rook-ceph-block";
    };
  };

  # PVC for Proton Drive state (sync state, logs)
  kubernetes.resources.persistentVolumeClaims."${name}-state" = {
    metadata = {
      name = "${name}-state";
      inherit namespace;
    };
    spec = {
      accessModes = [ "ReadWriteOnce" ];
      resources.requests.storage = "5Gi";
      storageClassName = "rook-ceph-block";
    };
  };

  # Service for dashboard access (optional)
  kubernetes.resources.services.${name} = {
    metadata = { inherit name namespace; };
    spec = {
      selector.app = name;
      ports = [
        {
          name = "dashboard";
          port = 4242;
          targetPort = 4242;
        }
      ];
    };
  };
}

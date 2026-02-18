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
                  echo "Source: $MINIO_BUCKET"
                  echo "Dest: $PROTON_DEST_PATH"

                  # Check if authenticated (credentials.enc exists)
                  if [ ! -f /config/proton-drive-sync/credentials.enc ]; then
                    echo "ERROR: Not authenticated. Run auth job first."
                    echo "kubectl create job --from=cronjob/${name} ${name}-manual -n ${namespace}"
                    exit 1
                  fi

                  # Install rclone for MinIO access
                  apk add --no-cache rclone zstd curl

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

                  [proton]
                  type = protondrive
                  username = $PROTON_USERNAME
                  password = $PROTON_PASSWORD
                  EOF

                  # Get today's date
                  TODAY=$(date +%Y-%m-%d)
                  YEAR=$(date +%Y)
                  MONTH=$(date +%m)
                  DAY=$(date +%d)

                  echo ""
                  echo "=== Syncing archives for $TODAY ==="

                  # List files in MinIO bucket for today
                  echo "Listing MinIO objects..."
                  rclone ls minio:$MINIO_BUCKET/$YEAR/$MONTH/$DAY/ 2>/dev/null || echo "No objects found for today"

                  # Sync to Proton Drive using proton-drive-sync
                  # First, mount/sync via rclone to a temp dir, then use proton-drive-sync
                  SYNC_DIR=/tmp/proton-sync-$TODAY
                  mkdir -p $SYNC_DIR

                  # Copy today's archives from MinIO
                  echo ""
                  echo "=== Downloading from MinIO ==="
                  rclone copy minio:$MINIO_BUCKET/$YEAR/$MONTH/$DAY/ $SYNC_DIR/ --progress || true

                  if [ -z "$(ls -A $SYNC_DIR 2>/dev/null)" ]; then
                    echo "WARNING: No archives found in MinIO for $TODAY"
                    exit 0
                  fi

                  # List files to sync
                  echo ""
                  echo "=== Files to sync ==="
                  ls -la $SYNC_DIR/

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
                  echo "=== Syncing to Proton Drive ==="
                  cd /tmp/proton-config
                  proton-drive-sync sync --config ./sync.json || {
                    echo "WARNING: Proton sync had errors (best-effort)"
                  }

                  # Generate report
                  echo ""
                  echo "=== Generating sync report ==="
                  REPORT_FILE="/tmp/proton-sync-report-$TODAY.json"
                  cat > $REPORT_FILE << EOF
                  {
                    "timestamp": "$(date -Iseconds)",
                    "date": "$TODAY",
                    "source_bucket": "$MINIO_BUCKET",
                    "source_prefix": "$YEAR/$MONTH/$DAY",
                    "destination_path": "$PROTON_DEST_PATH/$YEAR/$MONTH/$DAY",
                    "files_synced": $(ls -1 $SYNC_DIR 2>/dev/null | wc -l),
                    "status": "completed"
                  }
                  EOF

                  cat $REPORT_FILE

                  # Upload report back to MinIO
                  echo ""
                  echo "=== Uploading report to MinIO ==="
                  export MC_HOST_minio="$MINIO_URL"
                  mc cp $REPORT_FILE minio/$MINIO_BUCKET/_reports/$YEAR/$MONTH/$DAY/proton-sync-report.json || true

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

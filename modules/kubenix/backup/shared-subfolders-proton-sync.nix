{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:16a036d070212ef665a4e4f4e8607fde9c6b33f7634ca62f5c8767ed91f67c8e";
  protonDestPath = "homelab/shared-archives";
  folders = homelab.kubernetes.sharedBackupFolders;
  foldersStr = builtins.concatStringsSep " " folders;
  foldersJson = builtins.toJSON folders;

  backupScript = ''
        set -euo pipefail

        cleanup() {
          echo "Cleaning up temp files..."
          rm -f /tmp/proton-backup-*.tar.gz /tmp/proton-backup-*.tar.gz.gpg
        }
        trap cleanup EXIT

        DATE="$(date +%Y-%m-%d)"
        TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
        MANIFEST_FILE="manifest-$DATE.json"

        SOURCE_ROOT="/shared"

        echo "=== Starting Proton Drive shared subfolders backup (tar.gz + gpg + rclone copy) ==="
        echo "Date: $DATE"
        echo "Timestamp: $TIMESTAMP"
        echo "Folders to backup: ${foldersStr}"
        echo "Destination: proton:Backups/${protonDestPath}/current/"

        # Ensure rclone config directory exists
        mkdir -p "$HOME/.config/rclone"

        # Check if proton configuration exists, if not create it
        if ! grep -q "\[proton\]" "$HOME/.config/rclone/rclone.conf" 2>/dev/null; then
          echo "Setting up initial Proton Drive rclone config..."
          OBSCURED_PASS="$(rclone obscure "$PROTON_PASSWORD")"
          cat >> "$HOME/.config/rclone/rclone.conf" <<RCLONE_EOF
    [proton]
    type = protondrive
    username = $PROTON_USERNAME
    password = $OBSCURED_PASS
    RCLONE_EOF
        fi

        # Ensure destination exists
        echo "Ensuring remote directory exists..."
        rclone mkdir "proton:Backups/${protonDestPath}" || true

        # Generate manifest header
        echo "Generating manifest..."
        MANIFEST_JSON="$MANIFEST_FILE.json.tmp"
        {
          echo "{"
          echo "  \"backup_date\": \"$DATE\","
          echo "  \"timestamp\": \"$TIMESTAMP\","
          echo "  \"source_root\": \"/shared\","
          echo "  \"method\": \"tar.gz-gpg-rclone-copy\","
          echo "  \"destination\": \"proton:Backups/${protonDestPath}/current/\","
          echo "  \"folders\": ${foldersJson},
          echo "  \"archives\": ["
        } > "$MANIFEST_JSON"

        FIRST_ARCHIVE=true
        for folder in ${foldersStr}; do
          if [ -d "$SOURCE_ROOT/$folder" ]; then
            echo "Processing folder: $folder"
            ARCHIVE_BASE="/tmp/proton-backup-$TIMESTAMP-$folder"
            TAR_FILE="$ARCHIVE_BASE.tar.gz"
            ENC_FILE="$TAR_FILE.gpg"

            # Create tar.gz archive
            echo "  Creating archive..."
            tar czf "$TAR_FILE" -C "$SOURCE_ROOT" "$folder"

            # Encrypt with gpg
            echo "  Encrypting..."
            gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" --symmetric --cipher-algo AES256 "$TAR_FILE"

            # Upload encrypted archive
            echo "  Uploading..."
            rclone copy "$ENC_FILE" "proton:Backups/${protonDestPath}/current/"

            # Record in manifest
            ARCHIVE_SIZE=$(stat -c%s "$ENC_FILE" 2>/dev/null || echo 0)
            if [ "$FIRST_ARCHIVE" = true ]; then
              FIRST_ARCHIVE=false
              echo "    {\"folder\": \"$folder\", \"archive\": \"$folder.tar.gz.gpg\", \"encrypted_size\": $ARCHIVE_SIZE}" >> "$MANIFEST_JSON"
            else
              echo "    ,{\"folder\": \"$folder\", \"archive\": \"$folder.tar.gz.gpg\", \"encrypted_size\": $ARCHIVE_SIZE}" >> "$MANIFEST_JSON"
            fi

            # Clean up temp files for this folder
            rm -f "$TAR_FILE" "$ENC_FILE"
            echo "  Done: $folder"
          else
            echo "Warning: folder $folder not found, skipping"
          fi
        done

        {
          echo "  ],"
          echo "  \"encryption\": \"gpg-symmetric-aes256\","
          echo "  \"exclusions\": [\".DS_Store\", \"Thumbs.db\"]"
          echo "}"
        } >> "$MANIFEST_JSON"

        mv "$MANIFEST_JSON" "$MANIFEST_FILE"

        # Upload manifest
        echo "Uploading manifest..."
        rclone copy "$MANIFEST_FILE" "proton:Backups/${protonDestPath}/manifests/"

        # Clean up manifest
        rm -f "$MANIFEST_FILE"

        echo "=== Proton Drive Backup completed successfully ==="
        echo "Destination: proton:Backups/${protonDestPath}/current/"
        echo "Manifest: proton:Backups/${protonDestPath}/manifests/$MANIFEST_FILE"
  '';
in
{
  kubernetes.resources = {
    cronJobs."shared-subfolders-proton-sync" = {
      metadata = {
        name = "shared-subfolders-proton-sync";
        inherit namespace;
      };
      spec = {
        schedule = "0 3 * * *"; # 3 AM daily (after minio backup at 1 AM)
        timeZone = "America/Sao_Paulo";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec = {
          backoffLimit = 2;
          activeDeadlineSeconds = 3600; # 1 hour timeout
          template.spec = {
            restartPolicy = "OnFailure";
            imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
            containers = [
              {
                name = "proton-sync";
                inherit image;
                command = [
                  "bash"
                  "-c"
                ];
                args = [ backupScript ];
                env = [
                  {
                    name = "HOME";
                    value = "/root";
                  }
                  {
                    name = "PROTON_DEST_PATH";
                    value = protonDestPath;
                  }
                  {
                    name = "PROTON_USERNAME";
                    valueFrom.secretKeyRef = {
                      name = "shared-subfolders-proton-sync-config";
                      key = "PROTON_USERNAME";
                    };
                  }
                  {
                    name = "PROTON_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "shared-subfolders-proton-sync-config";
                      key = "PROTON_PASSWORD";
                    };
                  }
                  {
                    name = "ENCRYPTION_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "shared-subfolders-proton-sync-config";
                      key = "ENCRYPTION_PASSWORD";
                    };
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                    ephemeral-storage = "1Gi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                    ephemeral-storage = "5Gi";
                  };
                };
                volumeMounts = [
                  {
                    name = "shared-storage";
                    mountPath = "/shared";
                    readOnly = true;
                  }
                  {
                    name = "proton-config";
                    mountPath = "/root/.config/rclone";
                  }
                  {
                    name = "proton-cache";
                    mountPath = "/root/.cache/rclone";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "shared-storage";
                persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
              }
              {
                name = "proton-config";
                persistentVolumeClaim.claimName = "shared-subfolders-proton-sync-config";
              }
              {
                name = "proton-cache";
                persistentVolumeClaim.claimName = "shared-subfolders-proton-sync-state";
              }
            ];
          };
        };
      };
    };

    # PVC for Proton Drive config (persistent auth credentials)
    persistentVolumeClaims."shared-subfolders-proton-sync-config" = {
      metadata = {
        name = "shared-subfolders-proton-sync-config";
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
        storageClassName = kubenix.lib.defaultStorageClass;
      };
    };

    # PVC for Proton Drive state (cache, logs)
    persistentVolumeClaims."shared-subfolders-proton-sync-state" = {
      metadata = {
        name = "shared-subfolders-proton-sync-state";
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
        storageClassName = kubenix.lib.defaultStorageClass;
      };
    };
  };
}

{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:541cc695cd9ab09f5a82b4b85b01f6aa396e3146bdc8bdf1071f1bc3ed00cdda";
  protonDestPath = "homelab/shared-archives";
  folders = homelab.kubernetes.sharedBackupFolders;
  foldersStr = builtins.concatStringsSep " " folders;
  foldersJson = builtins.toJSON folders;

  backupScript = ''
        set -euo pipefail

        cleanup() {
          echo "Cleaning up temp files..."
          rm -rf /root/.cache/rclone/backup-tmp
        }
        trap cleanup EXIT

        DATE="$(date +%Y-%m-%d)"
        TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
        MANIFEST_FILE="manifest-$DATE.json"

        SOURCE_ROOT="/shared"
        TEMP_DIR="/root/.cache/rclone/backup-tmp"
        mkdir -p "$TEMP_DIR"

        echo "=== Starting Proton Drive shared subfolders backup (tar.gz + gpg + rclone copy) ==="
        echo "Date: $DATE"
        echo "Timestamp: $TIMESTAMP"
        echo "Folders to backup: ${foldersStr}"
        echo "Destination: proton:Backups/${protonDestPath}/current/"
        FOLDERS_JSON='${foldersJson}'

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
        MANIFEST_JSON="$TEMP_DIR/$MANIFEST_FILE"
        {
          echo "{"
          echo "  \"backup_date\": \"$DATE\","
          echo "  \"timestamp\": \"$TIMESTAMP\","
          echo "  \"source_root\": \"/shared\","
          echo "  \"method\": \"tar.gz-gpg-rclone-copy\","
          echo "  \"destination\": \"proton:Backups/${protonDestPath}/current/\","
          echo "  \"folders\": $FOLDERS_JSON,"
          echo "  \"archives\": ["
        } > "$MANIFEST_JSON"

        FIRST_ARCHIVE=true
        FAILED=0
        for folder in ${foldersStr}; do
          if [ -d "$SOURCE_ROOT/$folder" ]; then
            echo "Processing folder: $folder"

            TEMP_GPG="$TEMP_DIR/$folder.tar.gz.gpg"
            rm -f "$TEMP_GPG"

            # Pipe: tar.gz → gpg encrypt → temp file on PVC
            echo "  Creating encrypted archive on PVC..."
            if ! tar czf - -C "$SOURCE_ROOT" "$folder" \
              | gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" --symmetric --cipher-algo AES256 --output "$TEMP_GPG" -; then
              echo "  ERROR: Failed to create encrypted archive for $folder"
              FAILED=$((FAILED + 1))
              rm -f "$TEMP_GPG"
              continue
            fi

            FILE_SIZE=$(stat -c %s "$TEMP_GPG" 2>/dev/null || echo "0")
            echo "  Uploading to Proton Drive ($FILE_SIZE bytes)..."
            if ! rclone copy "$TEMP_GPG" "proton:Backups/${protonDestPath}/current/"; then
              echo "  ERROR: Failed to upload $folder"
              FAILED=$((FAILED + 1))
              rm -f "$TEMP_GPG"
              continue
            fi

            rm -f "$TEMP_GPG"
            echo "  Done: $folder"

            # Record in manifest
            if [ "$FIRST_ARCHIVE" = true ]; then
              FIRST_ARCHIVE=false
            else
              echo "," >> "$MANIFEST_JSON"
            fi
            echo "    {\"folder\": \"$folder\", \"archive\": \"$folder.tar.gz.gpg\", \"encrypted_size\": $FILE_SIZE}" >> "$MANIFEST_JSON"
          else
            echo "Warning: folder $folder not found, skipping"
          fi
        done

        # Complete manifest
        {
          echo ""
          echo "  ],"
          echo "  \"encryption\": \"gpg-symmetric-aes256\","
          echo "  \"exclusions\": [\".DS_Store\", \"Thumbs.db\"]"
          echo "}"
        } >> "$MANIFEST_JSON"

        if [ "$FAILED" -gt 0 ]; then
          echo "ERROR: $FAILED folder(s) failed to backup"
          exit 1
        fi

        # Upload manifest
        echo "Uploading manifest..."
        rclone copyto "$MANIFEST_JSON" "proton:Backups/${protonDestPath}/manifests/$MANIFEST_FILE" || true

        echo "=== Backup completed successfully ==="
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
          activeDeadlineSeconds = 7200; # 2 hour timeout
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
                    ephemeral-storage = "512Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                    ephemeral-storage = "1Gi";
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
        resources.requests.storage = "100Gi";
        storageClassName = kubenix.lib.defaultStorageClass;
      };
    };
  };
}

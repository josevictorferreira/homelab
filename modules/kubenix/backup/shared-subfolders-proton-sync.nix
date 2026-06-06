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

        DATE="$(date +%Y-%m-%d)"
        TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
        MANIFEST_FILE="manifest-$DATE.json"

        SOURCE_ROOT="/shared"

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
        MANIFEST_JSON="$MANIFEST_FILE.json.tmp"
        {
          echo "{"
          echo "  \"backup_date\": \"$DATE\","
          echo "  \"timestamp\": \"$TIMESTAMP\","
          echo "  \"source_root\": \"/shared\","
          echo "  \"method\": \"tar.gz-gpg-rclone-pipe\","
          echo "  \"destination\": \"proton:Backups/${protonDestPath}/current/\","
          echo "  \"folders\": $FOLDERS_JSON,"
          echo "  \"archives\": ["
        } > "$MANIFEST_JSON"

        FIRST_ARCHIVE=true
        FAILED=0
        for folder in ${foldersStr}; do
          if [ -d "$SOURCE_ROOT/$folder" ]; then
            echo "Processing folder: $folder"

            # Pipe: tar.gz → gpg encrypt → rclone upload (no temp files on disk)
            echo "  Creating archive, encrypting, and uploading..."
            # Delete existing file first (Proton Drive rejects overwrites via rcat)
            rclone delete "proton:Backups/${protonDestPath}/current/$folder.tar.gz.gpg" 2>/dev/null || true

            if tar czf - -C "$SOURCE_ROOT" "$folder" \
              | gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" --symmetric --cipher-algo AES256 --output - \
              | rclone rcat "proton:Backups/${protonDestPath}/current/$folder.tar.gz.gpg"; then
              echo "  Done: $folder"
            else
              echo "  ERROR: Failed to process $folder"
              FAILED=$((FAILED + 1))
              continue
            fi

            # Record in manifest (size unknown with pipe, set to 0)
            if [ "$FIRST_ARCHIVE" = true ]; then
              FIRST_ARCHIVE=false
              echo "    {\"folder\": \"$folder\", \"archive\": \"$folder.tar.gz.gpg\", \"encrypted_size\": 0}" >> "$MANIFEST_JSON"
            else
              echo "    ,{\"folder\": \"$folder\", \"archive\": \"$folder.tar.gz.gpg\", \"encrypted_size\": 0}" >> "$MANIFEST_JSON"
            fi
          else
            echo "Warning: folder $folder not found, skipping"
          fi
        done

        if [ "$FAILED" -gt 0 ]; then
          echo "ERROR: $FAILED folder(s) failed to backup"
          exit 1
        fi

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
        echo "=== Backup complete ==="
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

{ kubenix, homelab, pkgs, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";
  protonDestPath = "homelab/shared-archives";

  backupScript = ''
            set -euo pipefail

            DATE="$(date +%Y-%m-%d)"
            TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
            MANIFEST_FILE="manifest-$DATE.json"

            SOURCE_ROOT=\"/shared\"

            echo \"=== Starting Proton Drive shared subfolders backup (rclone sync) ===\"
            echo \"Date: $DATE\"
            echo \"Timestamp: $TIMESTAMP\"
            echo \"Folders to backup: notetaking images backups\"
            echo \"Destination: proton:Backups/''${PROTON_DEST_PATH}/current/\"

            # Ensure rclone config directory exists
            mkdir -p \"$HOME/.config/rclone\"

            # Check if proton configuration exists, if not create it
            if ! grep -q \"\[proton\]\" \"$HOME/.config/rclone/rclone.conf\" 2>/dev/null; then
              echo \"Setting up initial Proton Drive rclone config...\"
              OBSCURED_PASS="$(rclone obscure "$PROTON_PASSWORD")"
              cat >> \"$HOME/.config/rclone/rclone.conf\" <<RCLONE_EOF
    [proton]
    type = protondrive
    username = $PROTON_USERNAME
    password = $OBSCURED_PASS
    RCLONE_EOF
            fi

            # Generate manifest of files
            echo \"Generating manifest...\"
            WORKDIR=\"/tmp/proton-backup-$TIMESTAMP\"
            mkdir -p \"$WORKDIR\"
            cd \"$WORKDIR\"

            echo \"{\" > \"$MANIFEST_FILE\"
            echo "  \"backup_date\": \"$DATE\"," >> "$MANIFEST_FILE"
            echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$MANIFEST_FILE"
            echo "  \"source_root\": \"/shared\"," >> "$MANIFEST_FILE"
            echo "  \"method\": \"rclone-sync-proton\"," >> "$MANIFEST_FILE"
            echo "  \"destination\": \"proton:Backups/''${PROTON_DEST_PATH}/current/\", \" >> \"$MANIFEST_FILE\""
            echo "  \"folders\": [ \"notetaking\", \"images\", \"backups\" ]," >> \"$MANIFEST_FILE\"
            echo \"  \\"
    folders\\": [\\"
    notetaking\\", \\"
    images\\", \\"
    backups\\"],\" >> \"$MANIFEST_FILE\"
            echo \"  \\"
    files\\": [\" >> \"$MANIFEST_FILE\"

            FIRST=true
            for folder in notetaking images backups; do
              if [ -d "$SOURCE_ROOT/$folder" ]; then
                while IFS= read -r -d $'\0' file; do
                  SIZE="$(stat -c%s "$file" 2>/dev/null || echo 0)"
                  MTIME="$(stat -c%Y "$file" 2>/dev/null || echo 0)"
                  RELPATH=$(echo "$file" | sed "s|^$SOURCE_ROOT/||")
                  if [ "$FIRST" = true ]; then
                    FIRST=false
                  else
                    echo \",\" >> \"$MANIFEST_FILE\"
                  fi
                  echo -n '        {"path": "'"$RELPATH"'", "size": $SIZE, "mtime": $MTIME}' >> "$MANIFEST_FILE"
                done < <(find "$SOURCE_ROOT/$folder" -type f ! -name ".DS_Store" ! -name "Thumbs.db" -print0 2>/dev/null)
              fi
            done

            echo \"\" >> \"$MANIFEST_FILE\"
            echo \"      ],\" >> \"$MANIFEST_FILE\"
            echo '      "exclusions": [".DS_Store", "Thumbs.db"]' >> "$MANIFEST_FILE"
            echo \"    }\" >> \"$MANIFEST_FILE\"

            # Ensure destination exists
            echo \"Ensuring remote directory exists...\"
            rclone mkdir \"proton:Backups/''${PROTON_DEST_PATH}\" || true

    # Sync each folder individually with filters
    echo \"Starting rclone sync to Proton Drive...\"
    for
    folder in notetaking images backups;
            echo \"Syncing folder: \$folder\"
            rclone sync \"$SOURCE_ROOT/$folder\" \"proton:Backups/''${PROTON_DEST_PATH}/current/\$folder/\" --exclude \".DS_Store\" --exclude \"Thumbs.db\" --fast-list --transfers 4 --checksum --stats-one-line --stats 30s --log-level INFO
    echo \"Syncing folder: \$folder\"
            echo \"Warning: folder \$folder not found, skipping\"
    --exclude \".DS_Store\" \
    --exclude \"Thumbs.db\" \
    --fast-list \
    --transfers 4 \
    --checksum \
            rclone copy \"$MANIFEST_FILE\" \"proton:Backups/''${PROTON_DEST_PATH}/manifests/\"
    --stats 30s \
    --log-level INFO
    else
    echo \"Warning: folder \$folder not found, skipping\"
    fi
            echo \"Destination: proton:Backups/''${PROTON_DEST_PATH}/current/\"
            echo \"Manifest: proton:Backups/''${PROTON_DEST_PATH}/manifests/$MANIFEST_FILE\"
  echo \"Uploading manifest...\"
    rclone copy \"$MANIFEST_FILE\" \"proton:Backups/''${PROTON_DEST_PATH}/manifests/\"

    # Clean up
    rm -rf \"$WORKDIR\"

    echo \"=== Proton Drive Backup completed successfully ===\"
    echo \"Destination: proton:Backups/''${PROTON_DEST_PATH}/current/\"
    echo \"Manifest: proton:Backups/''${PROTON_DEST_PATH}/manifests/$MANIFEST_FILE\"
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
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                    ephemeral-storage = "1Gi";
                  };
                  limits = {
                    cpu = "1000m";
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
                persistentVolumeClaim.claimName = "cephfs-shared-storage-root";
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
        storageClassName = "rook-ceph-block";
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
        storageClassName = "rook-ceph-block";
      };
    };
  };
}







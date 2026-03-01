{ homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";
  minioEndpoint = "http://10.10.10.209:9000";
  bucket = "homelab-backup-shared";

  backupScript = ''
        set -euo pipefail

        DATE="$(date +%Y-%m-%d)"
        TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
        MANIFEST_FILE="manifest-$DATE.json"

        SOURCE_ROOT="/shared"

        echo "=== Starting shared subfolders backup (rclone sync) ==="
        echo "Date: $DATE"
        echo "Timestamp: $TIMESTAMP"
        echo "Folders to backup: notetaking images backups openclaw"
        echo "Destination: s3:${bucket}/"

        # Create rclone config
        mkdir -p "$HOME/.config/rclone"
        
        # Trim any whitespace/newlines from credentials
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

        # Generate manifest of files
        echo "Generating manifest..."
        WORKDIR="/tmp/backup-$TIMESTAMP"
        mkdir -p "$WORKDIR"
        cd "$WORKDIR"

        echo "{" > "$MANIFEST_FILE"
        echo "  \"backup_date\": \"$DATE\"," >> "$MANIFEST_FILE"
        echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$MANIFEST_FILE"
        echo "  \"source_root\": \"/shared\"," >> "$MANIFEST_FILE"
        echo "  \"method\": \"rclone-sync\"," >> "$MANIFEST_FILE"
        echo "  \"destination\": \"s3:${bucket}/current/\"," >> "$MANIFEST_FILE"
        echo "  \"folders\": [\"notetaking\", \"images\", \"backups\", \"openclaw\"]," >> "$MANIFEST_FILE"
        echo "  \"files\": [" >> "$MANIFEST_FILE"

        FIRST=true
        for folder in notetaking images backups openclaw; do
          if [ -d "$SOURCE_ROOT/$folder" ]; then
            while IFS= read -r -d $'\0' file; do
              SIZE="$(stat -c%s "$file" 2>/dev/null || echo 0)"
              MTIME="$(stat -c%Y "$file" 2>/dev/null || echo 0)"
              RELPATH="''${file#$SOURCE_ROOT/}"
              if [ "$FIRST" = true ]; then
                FIRST=false
              else
                echo "," >> "$MANIFEST_FILE"
              fi
              echo -n "        {\"path\": \"$RELPATH\", \"size\": $SIZE, \"mtime\": $MTIME}" >> "$MANIFEST_FILE"
            done < <(find "$SOURCE_ROOT/$folder" -type f ! -name ".DS_Store" ! -name "Thumbs.db" -print0 2>/dev/null)
          fi
        done

        echo "" >> "$MANIFEST_FILE"
        echo "      ]," >> "$MANIFEST_FILE"
        echo "      \"exclusions\": [\".DS_Store\", \"Thumbs.db\"]" >> "$MANIFEST_FILE"
        echo "    }" >> "$MANIFEST_FILE"

        # Ensure bucket exists
        echo "Ensuring bucket exists..."
        rclone mkdir "minio:${bucket}"

        # Sync each folder individually with filters
        echo "Starting rclone sync..."
        for folder in notetaking images backups openclaw; do
          if [ -d "$SOURCE_ROOT/$folder" ]; then
            echo "Syncing folder: $folder"
            rclone sync "$SOURCE_ROOT/$folder" "minio:${bucket}/current/$folder/" \
              --exclude ".DS_Store" \
              --exclude "Thumbs.db" \
              --fast-list \
              --transfers 4 \
              --checksum \
              --stats-one-line \
              --stats 30s \
              --log-level INFO
          else
            echo "Warning: folder $folder not found, skipping"
          fi
        done

        # Upload manifest
        echo "Uploading manifest..."
        rclone copy "$MANIFEST_FILE" "minio:${bucket}/manifests/"

        # Clean up
        rm -rf "$WORKDIR"

        echo "=== Backup completed successfully ==="
        echo "Destination: s3:${bucket}/current/"
        echo "Manifest: s3:${bucket}/manifests/$MANIFEST_FILE"
  '';
in
{
  kubernetes.resources.cronJobs."shared-subfolders-backup" = {
    metadata = {
      name = "shared-subfolders-backup";
      inherit namespace;
    };
    spec = {
      schedule = "0 1 * * *";
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 2;
        template.spec = {
          restartPolicy = "OnFailure";
          imagePullSecrets = [{ name = "ghcr-registry-secret"; }];
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
                  ephemeral-storage = "256Mi";
                };
                limits = {
                  cpu = "1000m";
                  memory = "1Gi";
                  ephemeral-storage = "512Mi";
                };
              };
              volumeMounts = [
                {
                  name = "shared-storage";
                  mountPath = "/shared";
                  readOnly = true;
                }
              ];
            }
          ];
          volumes = [
            {
              name = "shared-storage";
              persistentVolumeClaim.claimName = "cephfs-shared-storage-root";
            }
          ];
        };
      };
    };
  };
}

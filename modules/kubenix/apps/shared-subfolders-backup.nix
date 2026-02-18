{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:7b3b1c5d8a4f2e9b6c4d3e8f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0";
  minioEndpoint = "http://10.10.10.209:9000";
  bucket = "homelab-backup-shared";

  backupScript = ''
    set -euo pipefail

    DATE="$(date +%Y-%m-%d)"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    ARCHIVE_NAME="shared-$DATE"
    ARCHIVE_FILE="$ARCHIVE_NAME.tar.zst"
    SHA256_FILE="$ARCHIVE_FILE.sha256"
    MANIFEST_FILE="$ARCHIVE_NAME.manifest.json"

    SOURCE_ROOT="/shared"
    DEST_PREFIX="$DATE"

    echo "=== Starting shared subfolders backup ==="
    echo "Date: $DATE"
    echo "Timestamp: $TIMESTAMP"
    echo "Folders to backup: notetaking images backups"

    WORKDIR="/tmp/backup-$TIMESTAMP"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    echo "Creating manifest..."
    echo "{" > "$MANIFEST_FILE"
    echo "  \"backup_date\": \"$DATE\"," >> "$MANIFEST_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$MANIFEST_FILE"
    echo "  \"source_root\": \"/shared\"," >> "$MANIFEST_FILE"
    echo "  \"folders\": [\"notetaking\", \"images\", \"backups\"]," >> "$MANIFEST_FILE"
    echo "  \"files\": [" >> "$MANIFEST_FILE"

    FIRST=true
    for folder in notetaking images backups; do
      if [ -d "$SOURCE_ROOT/$folder" ]; then
        find "$SOURCE_ROOT/$folder" -type f ! -name ".DS_Store" ! -name "Thumbs.db" -print0 2>/dev/null | while IFS= read -r -d '''' file; do
          SIZE="$(stat -c%s "''''file" 2>/dev/null || echo 0)"
          MTIME="$(stat -c%Y "''''file" 2>/dev/null || echo 0)"
          RELPATH="''''{file#''''SOURCE_ROOT/}"
          if [ "$FIRST" = true ]; then
            FIRST=false
          else
            echo "," >> "$MANIFEST_FILE"
          fi
          echo -n "        {\"path\": \"$RELPATH\", \"size\": $SIZE, \"mtime\": $MTIME}" >> "$MANIFEST_FILE"
        done
      fi
    done

    echo "" >> "$MANIFEST_FILE"
    echo "      ]," >> "$MANIFEST_FILE"
    echo "      \"exclusions\": [\".DS_Store\", \"Thumbs.db\"]" >> "$MANIFEST_FILE"
    echo "    }" >> "$MANIFEST_FILE"

    echo "Creating tar.zst archive..."
    tar --zstd -cf "$ARCHIVE_FILE" \
      --exclude=".DS_Store" \
      --exclude="Thumbs.db" \
      -C "$SOURCE_ROOT" \
      notetaking images backups

    echo "Generating SHA256 checksum..."
    sha256sum "$ARCHIVE_FILE" > "$SHA256_FILE"

    echo "Archive size: $(du -h "$ARCHIVE_FILE" | cut -f1)"

    echo "Uploading to MinIO..."
    mc alias set shared "$MINIO_ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"
    mc mb --ignore-existing "shared/${bucket}"

    mc cp "$ARCHIVE_FILE" "shared/${bucket}/$DEST_PREFIX/$ARCHIVE_FILE.tmp"
    mc mv "shared/${bucket}/$DEST_PREFIX/$ARCHIVE_FILE.tmp" "shared/${bucket}/$DEST_PREFIX/$ARCHIVE_FILE"

    mc cp "$SHA256_FILE" "shared/${bucket}/$DEST_PREFIX/$SHA256_FILE.tmp"
    mc mv "shared/${bucket}/$DEST_PREFIX/$SHA256_FILE.tmp" "shared/${bucket}/$DEST_PREFIX/$SHA256_FILE"

    mc cp "$MANIFEST_FILE" "shared/${bucket}/$DEST_PREFIX/$MANIFEST_FILE.tmp"
    mc mv "shared/${bucket}/$DEST_PREFIX/$MANIFEST_FILE.tmp" "shared/${bucket}/$DEST_PREFIX/$MANIFEST_FILE"

    echo "Verifying uploads..."
    mc stat "shared/${bucket}/$DEST_PREFIX/$ARCHIVE_FILE"
    mc stat "shared/${bucket}/$DEST_PREFIX/$SHA256_FILE"
    mc stat "shared/${bucket}/$DEST_PREFIX/$MANIFEST_FILE"

    echo "Verifying checksum..."
    mc cat "shared/${bucket}/$DEST_PREFIX/$ARCHIVE_FILE" | sha256sum -c "$SHA256_FILE"

    rm -rf "$WORKDIR"

    echo "=== Backup completed successfully ==="
    echo "Archive: s3://${bucket}/$DEST_PREFIX/$ARCHIVE_FILE"
  '';
in
{
  kubernetes.resources.cronJobs."shared-subfolders-backup" = {
    metadata = {
      name = "shared-subfolders-backup";
      namespace = namespace;
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
                  ephemeral-storage = "2Gi";
                };
                limits = {
                  cpu = "1000m";
                  memory = "1Gi";
                  ephemeral-storage = "10Gi";
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

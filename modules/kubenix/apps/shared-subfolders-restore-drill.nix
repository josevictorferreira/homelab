{
  kubenix,
  homelab,
  lib,
  ...
}:

let
  namespace = homelab.kubernetes.namespaces.applications;
  toolboxImage = "ghcr.io/josevictorferreira/backup-toolbox@sha256:143dc0beafb3865fdd37d5a85bb814654063061af96e610ea53a2e9900c2da55";
  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-shared";

  expectedFolders = [
    "notetaking"
    "images"
    "backups"
  ];

  restoreScript = ''
    set -euo pipefail
    echo "=== Shared subfolders restore drill starting ==="

    echo "Setting up mc alias..."
    mc alias set backup "$MINIO_ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

    echo "Finding latest backup..."
    LATEST=$(mc ls --recursive --json "backup/${minioBucket}/" | \
      jq -r 'select(.key | test("shared-subfolders\\.tar\\.zst$")) | .lastModified + " " + .key' | \
      sort -r | head -1 | cut -d' ' -f2- || true)

    if [ -z "$LATEST" ]; then
      echo "ERROR: No backup found in MinIO"
      exit 1
    fi
    echo "Latest backup: $LATEST"

    LATEST_DIR=$(dirname "$LATEST")

    echo "Downloading backup + checksum..."
    mc cp "backup/${minioBucket}/$LATEST" /tmp/shared-subfolders.tar.zst
    mc cp "backup/${minioBucket}/$LATEST_DIR/shared-subfolders.tar.zst.sha256" /tmp/shared-subfolders.tar.zst.sha256

    echo "Verifying sha256..."
    cd /tmp
    if sha256sum -c shared-subfolders.tar.zst.sha256; then
      echo "sha256 OK"
    else
      echo "ERROR: sha256 mismatch"
      exit 1
    fi

    echo "Extracting archive..."
    mkdir -p /tmp/extracted
    zstd -dc /tmp/shared-subfolders.tar.zst | tar -xf - -C /tmp/extracted
    rm /tmp/shared-subfolders.tar.zst

    echo "Verifying expected folders exist..."
    SMOKE_OK=true
    for folder in ${builtins.toString expectedFolders}; do
      if [ -d "/tmp/extracted/$folder" ]; then
        echo "OK: folder $folder exists"
      else
        echo "FAIL: folder $folder missing"
        SMOKE_OK=false
      fi
    done

    if [ "$SMOKE_OK" = true ]; then
      echo "smoke OK"
      echo "=== Shared subfolders restore drill complete ==="
      exit 0
    else
      echo "ERROR: folder verification failed"
      exit 1
    fi
  '';
in
{
  kubernetes.resources.cronJobs."shared-subfolders-restore-drill" = {
    metadata = {
      name = "shared-subfolders-restore-drill";
      namespace = namespace;
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

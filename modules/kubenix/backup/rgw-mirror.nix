{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
  image = "rclone/rclone@sha256:40ec2cb10bbfcf78e5cbbdf2c7180fd821a115ee3b589d19fc4e92d13293d378";
  rgwEndpoint = kubenix.lib.objectStoreEndpoint;
  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-rgw";
  buckets = [
    "imgproxy"
    "linkwarden-files"
    "n8n-files"
    "open-webui-files"
    "valoris-s3"
  ];

  mirrorScript = ''
    set -euo pipefail
    echo "=== RGW → MinIO mirror starting ==="
    DATE=''$(date +%Y/%m/%d)
    FAILED=0
    REPORT=/tmp/sync-report.txt
    : > "''$REPORT"

    export RCLONE_CONFIG_RGW_TYPE=s3
    export RCLONE_CONFIG_RGW_PROVIDER=Ceph
    export RCLONE_CONFIG_RGW_ENDPOINT="${rgwEndpoint}"
    export RCLONE_CONFIG_RGW_NO_CHECK_BUCKET=true

    export RCLONE_CONFIG_MINIO_TYPE=s3
    export RCLONE_CONFIG_MINIO_PROVIDER=Minio
    export RCLONE_CONFIG_MINIO_ENDPOINT="${minioEndpoint}"

    BUCKETS="${builtins.concatStringsSep " " buckets}"

    for BUCKET in ''$BUCKETS; do
      echo "--- Syncing ''$BUCKET ---"
      if rclone sync "rgw:''$BUCKET" "minio:${minioBucket}/''$BUCKET" \
        --checksum \
        --delete-after \
        --retries 10 \
        --retries-sleep 5s \
        --transfers 4 \
        --checkers 8 \
        --stats-one-line \
        --stats 30s \
        --log-level INFO 2>&1 | tee "/tmp/rclone-''$BUCKET.log"; then
        echo "OK  ''$BUCKET" >> "''$REPORT"
      else
        echo "FAIL ''$BUCKET" >> "''$REPORT"
        FAILED=$((''$FAILED + 1))
      fi
    done

    echo "--- Uploading report ---"
    rclone copy "''$REPORT" "minio:${minioBucket}/_reports/''$DATE/" \
      --log-level INFO

    if [ "''$FAILED" -gt 0 ]; then
      echo "=== ''$FAILED bucket(s) failed ==="
      cat "''$REPORT"
      exit 1
    fi

    echo "=== RGW → MinIO mirror complete ==="
    cat "''$REPORT"
  '';
in
{
  kubernetes.resources.cronJobs."rgw-mirror" = {
    metadata = {
      name = "rgw-mirror";
      inherit namespace;
    };
    spec = {
      schedule = "0 4 * * *";
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
              name = "rgw-mirror";
              inherit image;
              command = [
                "sh"
                "-c"
              ];
              args = [ mirrorScript ];
              env = [
                {
                  name = "RCLONE_CONFIG_RGW_ACCESS_KEY_ID";
                  valueFrom.secretKeyRef = {
                    name = "rgw-mirror-s3-credentials";
                    key = "RCLONE_CONFIG_RGW_ACCESS_KEY_ID";
                  };
                }
                {
                  name = "RCLONE_CONFIG_RGW_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "rgw-mirror-s3-credentials";
                    key = "RCLONE_CONFIG_RGW_SECRET_ACCESS_KEY";
                  };
                }
                {
                  name = "RCLONE_CONFIG_MINIO_ACCESS_KEY_ID";
                  valueFrom.secretKeyRef = {
                    name = "rgw-mirror-s3-credentials";
                    key = "RCLONE_CONFIG_MINIO_ACCESS_KEY_ID";
                  };
                }
                {
                  name = "RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "rgw-mirror-s3-credentials";
                    key = "RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY";
                  };
                }
              ];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "1";
                  memory = "512Mi";
                };
              };
            }
          ];
        };
      };
    };
  };
}

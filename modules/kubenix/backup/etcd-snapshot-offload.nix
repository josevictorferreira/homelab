{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;

  image = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";

  minioEndpoint = "http://10.10.10.209:9000";
  minioBucket = "homelab-backup-etcd";
  mcAlias = "backup";

  snapshotHostPath = "/var/lib/rancher/k3s/server/db/snapshots";

  script = ''
    #!/bin/sh
    set -euo pipefail

    echo "=== etcd snapshot offload: $(date -Iseconds) ==="

    # Configure mc alias
    mc alias set ${mcAlias} ${minioEndpoint} "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

    # Get hostname for path partitioning
    NODE=$(cat /etc/hostname 2>/dev/null || hostname)

    echo "Node: $NODE"
    echo "Scanning snapshots in /snapshots/ ..."

    UPLOADED=0
    SKIPPED=0

    for snap in /snapshots/etcd-snapshot-*; do
      [ -f "$snap" ] || continue
      FILENAME=$(basename "$snap")
      REMOTE_PATH="${mcAlias}/${minioBucket}/$NODE/$FILENAME"

      # Skip if already uploaded (idempotent)
      if mc stat "$REMOTE_PATH" >/dev/null 2>&1; then
        SKIPPED=$((SKIPPED + 1))
        continue
      fi

      echo "Uploading: $FILENAME"
      mc cp "$snap" "$REMOTE_PATH"
      UPLOADED=$((UPLOADED + 1))
    done

    echo "=== Done: uploaded=$UPLOADED skipped=$SKIPPED ==="
  '';
in
{
  kubernetes.resources.cronJobs."etcd-snapshot-offload" = {
    metadata = {
      namespace = namespace;
      labels."app.kubernetes.io/name" = "etcd-snapshot-offload";
    };
    spec = {
      schedule = "30 */12 * * *";
      timeZone = "America/Sao_Paulo";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 1;
        activeDeadlineSeconds = 600;
        template.spec = {
          restartPolicy = "Never";
          nodeSelector = {
            "node-role.kubernetes.io/master" = "true";
          };
          tolerations = [
            {
              key = "node-role.kubernetes.io/master";
              operator = "Exists";
              effect = "NoSchedule";
            }
            {
              key = "node-role.kubernetes.io/control-plane";
              operator = "Exists";
              effect = "NoSchedule";
            }
          ];
          containers = [
            {
              name = "offload";
              inherit image;
              command = [
                "/bin/sh"
                "-c"
                script
              ];
              envFrom = [
                {
                  secretRef.name = "etcd-snapshot-offload-s3-credentials";
                }
              ];
              volumeMounts = [
                {
                  name = "etcd-snapshots";
                  mountPath = "/snapshots";
                  readOnly = true;
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "256Mi";
                };
              };
            }
          ];
          volumes = [
            {
              name = "etcd-snapshots";
              hostPath = {
                path = snapshotHostPath;
                type = "Directory";
              };
            }
          ];
        };
      };
    };
  };
}

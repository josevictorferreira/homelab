{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
in

{
  kubernetes.objects = [
    {
      apiVersion = "monitoring.coreos.com/v1";
      kind = "PrometheusRule";
      metadata = {
        name = "backup-alerts";
        inherit namespace;
        labels = {
          "app.kubernetes.io/part-of" = "backup-observability";
          release = "kube-prometheus-stack";
        };
      };
      spec.groups = [
        # ── MinIO storage ──
        {
          name = "minio.rules";
          rules = [
            {
              alert = "MinIOCapacityWarning";
              expr = "100 * (1 - (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes)) > 85";
              "for" = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "MinIO storage usage above 85%";
                description = "MinIO cluster is {{ $value | printf \"%.0f\" }}% full. Consider expanding storage or cleaning up old backups.";
              };
            }
            {
              alert = "MinIOCapacityCritical";
              expr = "100 * (1 - (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes)) > 95";
              "for" = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "MinIO storage usage above 95%";
                description = "MinIO cluster is {{ $value | printf \"%.0f\" }}% full. Backups may start failing.";
              };
            }
          ];
        }

        # ── Velero ──
        {
          name = "velero.rules";
          rules = [
            {
              alert = "VeleroBackupFailure";
              expr = "increase(velero_backup_failure_total[1h]) > 0";
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Velero backup failed";
                description = "Velero backup schedule {{ $labels.schedule }} had {{ $value }} failure(s) in the last hour.";
              };
            }
            {
              alert = "VeleroBackupPartialFailure";
              expr = "increase(velero_backup_partial_failure_total[1h]) > 0";
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Velero backup partially failed";
                description = "Velero backup schedule {{ $labels.schedule }} had {{ $value }} partial failure(s) in the last hour.";
              };
            }
            {
              alert = "VeleroBackupStale";
              expr = ''time() - velero_backup_last_successful_timestamp{schedule="daily-backup"} > 93600'';
              "for" = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "Velero daily backup is stale";
                description = "No successful Velero backup for schedule {{ $labels.schedule }} in over 26 hours.";
              };
            }
          ];
        }

        # ── Postgres backup/restore ──
        {
          name = "postgres-backup.rules";
          rules = [
            {
              alert = "PostgresBackupJobFailed";
              expr = ''increase(kube_job_status_failed{namespace="apps", job_name=~"postgres-backup.*"}[6h]) > 0'';
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Postgres backup job failed";
                description = "Job {{ $labels.job_name }} in namespace {{ $labels.namespace }} has failed.";
              };
            }
            {
              alert = "PostgresBackupStale";
              expr = ''time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="postgres-backup"} > 93600'';
              "for" = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "Postgres backup is stale";
                description = "No successful postgres-backup run in over 26 hours.";
              };
            }
            {
              alert = "PostgresRestoreDrillFailed";
              expr = ''increase(kube_job_status_failed{namespace="apps", job_name=~"postgres-restore-drill.*"}[168h]) > 0'';
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Postgres restore drill failed";
                description = "Job {{ $labels.job_name }} in namespace {{ $labels.namespace }} has failed. Restore capability may be compromised.";
              };
            }
            {
              alert = "PostgresRestoreDrillStale";
              expr = ''time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="postgres-restore-drill"} > 604800'';
              "for" = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "Postgres restore drill is stale";
                description = "No successful postgres-restore-drill run in over 7 days.";
              };
            }
          ];
        }
      ];
    }
  ];
}

{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  datasourceUid = "prometheus";

  # Alert rule helper — Grafana Unified Alerting provisioning format
  mkPromRule =
    {
      uid,
      title,
      expr,
      forDuration ? "5m",
      severity ? "critical",
      summary,
      description,
    }:
    {
      inherit uid title;
      condition = "C";
      "for" = forDuration;
      labels = { inherit severity; };
      annotations = { inherit summary description; };
      data = [
        {
          refId = "A";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = datasourceUid;
          model = {
            inherit expr;
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "A";
          };
        }
        {
          refId = "C";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = "__expr__";
          model = {
            type = "threshold";
            expression = "A";
            refId = "C";
            conditions = [
              {
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
              }
            ];
          };
        }
      ];
    };

  alertRules = {
    apiVersion = 1;
    groups = [
      {
        orgId = 1;
        name = "Backup - MinIO";
        folder = "Backup Alerts";
        interval = "5m";
        rules = [
          (mkPromRule {
            uid = "backup-minio-capacity-warning";
            title = "MinIO Capacity Warning (>85%)";
            expr = "100 * (1 - (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes)) > 85";
            forDuration = "30m";
            severity = "warning";
            summary = "MinIO storage usage above 85%";
            description = "MinIO cluster is {{ $value }}% full.";
          })
          (mkPromRule {
            uid = "backup-minio-capacity-critical";
            title = "MinIO Capacity Critical (>95%)";
            expr = "100 * (1 - (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes)) > 95";
            forDuration = "15m";
            severity = "critical";
            summary = "MinIO storage above 95%";
            description = "MinIO cluster is {{ $value }}% full. Backups may fail.";
          })
        ];
      }
      {
        orgId = 1;
        name = "Backup - Velero";
        folder = "Backup Alerts";
        interval = "5m";
        rules = [
          (mkPromRule {
            uid = "backup-velero-failure";
            title = "Velero Backup Failure";
            expr = "increase(velero_backup_failure_total[1h]) > 0";
            severity = "critical";
            summary = "Velero backup failed";
            description = "Velero backup had failures in the last hour.";
          })
          (mkPromRule {
            uid = "backup-velero-partial-failure";
            title = "Velero Backup Partial Failure";
            expr = "increase(velero_backup_partial_failure_total[1h]) > 0";
            severity = "warning";
            summary = "Velero backup partially failed";
            description = "Velero backup had partial failures in the last hour.";
          })
          (mkPromRule {
            uid = "backup-velero-stale";
            title = "Velero Daily Backup Stale (>26h)";
            expr = ''time() - velero_backup_last_successful_timestamp{schedule="daily-backup"} > 93600'';
            forDuration = "15m";
            severity = "critical";
            summary = "No successful Velero backup in 26+ hours";
            description = "Schedule daily-backup has not succeeded in over 26 hours.";
          })
        ];
      }
      {
        orgId = 1;
        name = "Backup - Postgres";
        folder = "Backup Alerts";
        interval = "5m";
        rules = [
          (mkPromRule {
            uid = "backup-pg-job-failed";
            title = "Postgres Backup Job Failed";
            expr = ''increase(kube_job_status_failed{namespace="apps", job_name=~"postgres-backup.*"}[6h]) > 0'';
            severity = "critical";
            summary = "Postgres backup job failed";
            description = "A postgres-backup job has failed in the last 6 hours.";
          })
          (mkPromRule {
            uid = "backup-pg-stale";
            title = "Postgres Backup Stale (>26h)";
            expr = ''time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="postgres-backup"} > 93600'';
            forDuration = "15m";
            severity = "critical";
            summary = "No successful postgres backup in 26+ hours";
            description = "CronJob postgres-backup has not succeeded in over 26 hours.";
          })
          (mkPromRule {
            uid = "backup-pg-drill-failed";
            title = "Postgres Restore Drill Failed";
            expr = ''increase(kube_job_status_failed{namespace="apps", job_name=~"postgres-restore-drill.*"}[168h]) > 0'';
            severity = "warning";
            summary = "Postgres restore drill failed";
            description = "A postgres-restore-drill job has failed in the last 7 days.";
          })
          (mkPromRule {
            uid = "backup-pg-drill-stale";
            title = "Postgres Restore Drill Stale (>7d)";
            expr = ''time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="postgres-restore-drill"} > 604800'';
            forDuration = "30m";
            severity = "warning";
            summary = "No successful postgres restore drill in 7+ days";
            description = "CronJob postgres-restore-drill has not succeeded in over 7 days.";
          })
        ];
      }
      {
        orgId = 1;
        name = "Backup - Shared Subfolders";
        folder = "Backup Alerts";
        interval = "5m";
        rules = [
          (mkPromRule {
            uid = "backup-shared-job-failed";
            title = "Shared Subfolders Backup Job Failed";
            expr = ''increase(kube_job_status_failed{namespace="apps", job_name=~"shared-subfolders-backup.*"}[6h]) > 0'';
            severity = "critical";
            summary = "Shared subfolders backup job failed";
            description = "A shared-subfolders-backup job has failed in the last 6 hours.";
          })
          (mkPromRule {
            uid = "backup-shared-stale";
            title = "Shared Subfolders Backup Stale (>26h)";
            expr = ''time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="shared-subfolders-backup"} > 93600'';
            forDuration = "15m";
            severity = "critical";
            summary = "No successful shared subfolders backup in 26+ hours";
            description = "CronJob shared-subfolders-backup has not succeeded in over 26 hours.";
          })
        ];
      }
    ];
  };
in
{
  kubernetes.resources.configMaps."grafana-alerting-backup-rules" = {
    metadata = {
      inherit namespace;
      labels = {
        grafana_alert = "1";
      };
    };
    data."backup-rules.yaml" = kubenix.lib.toYamlStr alertRules;
  };
}

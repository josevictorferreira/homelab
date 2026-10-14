{ lib, kubenix, homelab, ... }:

# Phase 6: barman ObjectStore, ScheduledBackup and Database CRs for the
# postgresql cluster (enabled 2026-09-16 after the restored data was verified).
let
  namespace = homelab.kubernetes.namespaces.databases;
  name = "postgresql";
  objectStoreName = "pi-minio";
  barmanPlugin = "barman-cloud.cloudnative-pg.io";

  # Kubernetes object names cannot contain "_".
  k8sName = db: builtins.replaceStrings [ "_" ] [ "-" ] db;
  mkDatabase = db: {
    name = k8sName db;
    value = {
      metadata = {
        name = k8sName db;
        inherit namespace;
      };
      spec = {
        name = db;
        owner = "postgres";
        cluster.name = name;
        databaseReclaimPolicy = "retain";
        extensions = [
          { name = "vector"; }
          { name = "vchord"; }
        ];
      };
    };
  };
in
{
  kubernetes.resources = {
    objectstore.${objectStoreName} = {
      metadata = {
        name = objectStoreName;
        inherit namespace;
      };
      spec = {
        configuration = {
          destinationPath = "s3://homelab-backup-postgres/cnpg";
          endpointURL = "http://10.10.10.209:9000";
          s3Credentials = {
            accessKeyId = {
              name = "postgresql-backup-s3";
              key = "ACCESS_KEY_ID";
            };
            secretAccessKey = {
              name = "postgresql-backup-s3";
              key = "ACCESS_SECRET_KEY";
            };
          };
          wal.compression = "zstd";
          # plugin-barman-cloud 0.8 only accepts bzip2/gzip/lz4/snappy for data.
          data.compression = "gzip";
        };
        retentionPolicy = "30d";
        # The sidecar runs barman-cloud-backup (3 python processes), wal-archive
        # and backup-delete at the same time; the namespace default of 256Mi
        # OOM-killed it mid-backup (2026-10-10, "error reading from server: EOF").
        instanceSidecarConfiguration.resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "1";
            memory = "1Gi";
          };
        };
      };
    };

    # CNPG schedules are six-field cron in UTC: 04:00 UTC = 01:00 America/Sao_Paulo,
    # ninety minutes before the logical `postgres-backup` dump (02:30 local) so the
    # two full reads of the database never overlap on this storage.
    scheduledbackup."${name}-daily" = {
      metadata = {
        name = "${name}-daily";
        inherit namespace;
      };
      spec = {
        schedule = "0 0 4 * * *";
        # The first base backup is taken by hand once Ceph recovery is done;
        # the ~22 GB read would compete with backfill on this storage.
        immediate = false;
        backupOwnerReference = "self";
        cluster.name = name;
        method = "plugin";
        pluginConfiguration.name = barmanPlugin;
      };
    };

    database = builtins.listToAttrs (map mkDatabase homelab.kubernetes.databases.postgres);
  };
}

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
        inherit name db;
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
          destinationPath = "s3://homelab-backup-postgres/cnpg/";
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
      };
    };

    # CNPG schedules are six-field cron in UTC: 05:30 UTC = 02:30 America/Sao_Paulo.
    scheduledbackup."${name}-daily" = {
      metadata = {
        name = "${name}-daily";
        inherit namespace;
      };
      spec = {
        schedule = "0 30 5 * * *";
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

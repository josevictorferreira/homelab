{ lib, kubenix, homelab, ... }:

# Phase 5 final cluster. Enable by renaming to postgresql.nix.
# Apps reach it at kubenix.lib.postgresHost (postgresql-rw.databases.svc).
let
  namespace = homelab.kubernetes.namespaces.databases;
  name = "postgresql";
  pg = import ./_postgresql-lib.nix;
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
    cluster.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        instances = 1;
        imageName = pg.image;
        imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
        enableSuperuserAccess = true;
        superuserSecret.name = "postgresql-superuser";
        inherit (pg) storage walStorage resources postgresql;

        plugins = [
          {
            name = barmanPlugin;
            isWALArchiver = true;
            parameters.barmanObjectName = objectStoreName;
          }
        ];

        managed.services.additional = [
          {
            selectorType = "rw";
            serviceTemplate = {
              metadata = {
                name = "${name}-lb";
                annotations = kubenix.lib.serviceAnnotationFor name;
              };
              spec.type = "LoadBalancer";
            };
          }
        ];
      } // pg.importFromPostgresql18;
    };

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
          data.compression = "zstd";
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
        immediate = true;
        backupOwnerReference = "self";
        cluster.name = name;
        method = "plugin";
        pluginConfiguration.name = barmanPlugin;
      };
    };

    database = builtins.listToAttrs (map mkDatabase homelab.kubernetes.databases.postgres);
  };
}

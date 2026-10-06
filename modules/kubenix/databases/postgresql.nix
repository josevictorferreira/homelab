{ kubenix, homelab, ... }:

# Production CNPG cluster. Data arrives via a rate-limited pg_dumpall restore
# from the workstation (see .agents/features/0002-postgres-operator-refactory/status.md,
# 2026-09-16), not via bootstrap.initdb.import: on this storage the import job's
# unthrottled I/O stalled etcd. Backups and Database CRs live in
# _postgresql-backups.nix and are enabled after the data is verified.
let
  namespace = homelab.kubernetes.namespaces.databases;
  name = "postgresql";
  pg = import ./_postgresql-lib.nix;
in
{
  kubernetes.resources.cluster.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      instances = 1;
      imageName = pg.image;
      imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
      enableSuperuserAccess = true;
      superuserSecret.name = "postgresql-superuser";
      inherit (pg) storage resources;
      # Grown from 8Gi on 2026-10-05: WAL filled up while archiving to the Pi
      # failed, and CNPG refuses to start PostgreSQL without WAL free space.
      walStorage = pg.walStorage // { size = "12Gi"; };
      postgresql = pg.postgresql // {
        parameters = pg.postgresql.parameters // {
          # Bulk restore: fewer checkpoints while data streams in.
          max_wal_size = "4GB";
        };
      };
      bootstrap.initdb.dataChecksums = true;
      plugins = [
        {
          name = "barman-cloud.cloudnative-pg.io";
          # Paused 2026-10-05: the Pi backup-pool is down (ZFS space-map panic), so
          # archiving failed and WAL piled up. CNPG still calls ArchiveWAL on any
          # enabled plugin, so the plugin itself is disabled. Restore both to true
          # once MinIO is healthy, then take a fresh base backup.
          enabled = false;
          isWALArchiver = false;
          parameters.barmanObjectName = "pi-minio";
        }
      ];

      # The Debian PostgreSQL 18 build raised SIGILL (invalid opcode inside the
      # postgres binary) on the Celeron N5105 nodes (no AVX) during the 2026-09-16
      # restore. Keep the instance on the AVX2-capable nodes.
      affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
        {
          matchExpressions = [
            {
              key = "kubernetes.io/hostname";
              operator = "In";
              values = [ "lab-beta-cp" "lab-delta-cp" ];
            }
          ];
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
    };
  };
}

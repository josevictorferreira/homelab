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
      inherit (pg) storage walStorage resources;
      postgresql = pg.postgresql // {
        parameters = pg.postgresql.parameters // {
          # Bulk restore: fewer checkpoints while data streams in.
          max_wal_size = "4GB";
        };
      };
      bootstrap.initdb.dataChecksums = true;

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

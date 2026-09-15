{ homelab, ... }:

# Phase 4 throwaway cluster: imports from postgresql-18 (read-only on the
# source), gets verified, then is deleted again. Enable by renaming to
# postgresql-rehearsal.nix; disable by renaming back (Flux prunes it + PVCs).
let
  namespace = homelab.kubernetes.namespaces.databases;
  name = "postgresql-rehearsal";
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
      inherit (pg) storage walStorage resources postgresql;
    } // pg.importFromPostgresql18;
  };
}

{ kubenix, homelab, ... }:

# Barman Cloud CNPG-I plugin: WAL archiving + base backups to an ObjectStore.
# Must live in the same namespace as the operator. Uses cert-manager for mTLS.
let
  namespace = homelab.kubernetes.namespaces.databases;
in
{
  kubernetes.helm.releases."plugin-barman-cloud" = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://cloudnative-pg.github.io/charts";
      chart = "plugin-barman-cloud";
      version = "0.8.0";
      sha256 = "sha256-oPhGA+7p2fstOLA7M7EQiYy381PqrO8AhqprGDChKhk=";
    };
    inherit namespace;
    includeCRDs = true;
    values = {
      resources = {
        requests = {
          cpu = "50m";
          memory = "128Mi";
        };
        limits = {
          cpu = "250m";
          memory = "256Mi";
        };
      };
    };
  };
}

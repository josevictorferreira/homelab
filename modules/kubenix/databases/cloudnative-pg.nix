{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.databases;
in
{
  kubernetes.helm.releases."cloudnative-pg" = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://cloudnative-pg.github.io/charts";
      chart = "cloudnative-pg";
      version = "0.29.0";
      sha256 = "sha256-kEFuvG5CsJ/iloIbBKcrDj1Ta0ZRxJ+KJ5LODMjbY8A=";
    };
    inherit namespace;
    includeCRDs = true;
    values = {
      config.clusterWide = true;
      monitoring.podMonitorEnabled = true;
      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
    };
  };
}

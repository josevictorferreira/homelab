{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.databases;
in
{
  kubernetes.helm.releases."cloudnative-pg" = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://cloudnative-pg.github.io/charts";
      chart = "cloudnative-pg";
      version = "0.29.1";
      sha256 = "sha256-VWDikb5gw9s35yZYk3BqcojQtEE/b3gdDN6TCcJXzZ4=";
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

{ kubenix, clusterConfig, ... }:

let
  namespace = "rook-ceph";
  domain = clusterConfig.domain;
in
{
  kubernetes = {
    helm.releases."rook-ceph-cluster" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.rook.io/release";
          chart = "rook-ceph-cluster";
          version = "1.17.7";
          sha256 = "sha256-UZdN6Z4Rr8N1BMWmD6IgyTOzPoKRhvjJYh+Y3vY3kEY=";
        };
      namespace = namespace;
      includeCRDs = true;
      noHooks = true;
      values = {
        cephClusterSpec = {
          mon.count = 3;
          storage = {
            useAllNodes = true;
            useAllDevices = true;
          };
          dashboard.enabled = true;
        };
        cephBlockPools = [
          {
            name = "replicapool";
            spec = {
              failureDomain = "host";
              replicated.size = 3;
            };
            storageClass = {
              enabled = true;
              name = "rook-ceph-block";
              isDefault = true;
              alllowVolumeExpansion = true;
              reclaimPolicy = "Delete";
            };
          }
        ];
        cephFileSystems = [
          {
            name = "ceph-filesystem";
            spec = {
              metadataPool.replicated.size = 3;
              dataPools = [{
                replicated.size = 3;
              }];
              metadataServer.activeCount = 1;
            };
            storageClass = {
              enabled = true;
              name = "rook-ceph-filesystem";
              pool = "data0";
              reclaimPolicy = "Delete";
              allowVolumeExpansion = true;
            };
          }
        ];

        ingress.dashboard = {
          enabled = true;
          ingressClassName = "cilium";
          host = {
            name = "ceph.${domain}";
            path = "/";
          };
          tls = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
        };
      };
    };
  };
}

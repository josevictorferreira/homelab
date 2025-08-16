{ kubenix, lib, clusterConfig, ... }:

let
  namespace = "rook-ceph";
  domain = clusterConfig.domain;
  storageNodes = clusterConfig.nodeGroup.k8sStorages;
  storageNodesList = lib.mapAttrsToList
    (name: attrs: {
      name = name;
      devices = builtins.map
        (device: {
          name = device;
        })
        attrs.storageDevices;
    })
    storageNodes;
in
{
  kubernetes = {
    customTypes = {
      cephblockpool = {
        attrName = "cephblockpool";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephBlockPool";
      };

      cephcluster = {
        attrName = "cephcluster";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephCluster";
      };

      cephfilesystem = {
        attrName = "cephfilesystem";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephFilesystem";
      };

      cephfilesystemsubvolumegroup = {
        attrName = "cephfilesystemsubvolumegroup";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephFilesystemSubVolumeGroup";
      };

      cephobjectstore = {
        attrName = "cephobjectstore";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephObjectStore";
      };
    };

    helm.releases."rook-ceph-cluster" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.rook.io/release";
          chart = "rook-ceph-cluster";
          version = "1.17.7";
          sha256 = "sha256-/TIeOE0BlivSAn4Wg3rS20IfTrfbSrybz/oLYfD3aSQ=";
        };
      namespace = namespace;
      includeCRDs = true;
      noHooks = true;
      values = {
        toolbox = {
          enabled = true;
          resources = {
            requests.cpu = "50m";
            requests.memory = "64Mi";
          };
        };
        cephClusterSpec = {
          mon.count = 3;
          mon.allowMultiplePerNode = true;
          dashboard.enabled = true;
          placement.all = {
            tolerations = [
              { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
            ];
          };
          resources = {
            mgr = {
              limits.memory = "1Gi";
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
            mon = {
              limits.memory = "2Gi";
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
            osd = {
              limits.memory = "4Gi";
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
            prepareosd = {
              requests.cpu = "50m";
              requests.memory = "50Mi";
            };
            "mgr-sidecar" = {
              requests.cpu = "50m";
              requests.memory = "40Mi";
            };
            crashcollector = {
              requests.cpu = "50m";
              requests.memory = "60Mi";
            };
            logcollector = {
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
            cleanup = {
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
            exporter = {
              requests.cpu = "50m";
              requests.memory = "64Mi";
            };
          };
          storage = {
            useAllNodes = false;
            useAllDevices = false;
            nodes = storageNodesList;
          };
          # cleanupPolicy = {
          #   confirmation = "yes-really-destroy-data";
          #   sanitizeDisks.method = "quick";
          # };
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
              allowVolumeExpansion = true;
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
          tls = [
            {
              hosts = [ "ceph.${domain}" ];
              secretName = "wildcard-tls";
            }
          ];
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
        };
      };
    };
  };
}

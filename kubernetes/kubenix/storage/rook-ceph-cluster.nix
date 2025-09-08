{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  domain = homelab.domain;
  storageNodes = homelab.nodes.group."k8s-storage".configs;
  storageNodesList = lib.mapAttrsToList
    (name: attrs: {
      name = name;
      devices = builtins.map
        (device: {
          name = device;
        })
        attrs.disks;
    })
    storageNodes;
  monitorGroupName = "k8s-control-plane"; # Name of the node group to run monitors on
  monitorHostNames = homelab.nodes.group.${monitorGroupName}.names;
in
{
  kubernetes = {
    helm.releases."rook-ceph-cluster" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.rook.io/release";
          chart = "rook-ceph-cluster";
          version = "1.18.1";
          sha256 = "sha256-lX9aDPUbfrZ8yuMKtKqDROX+MWQFB8gYHTlOm27FfaE=";
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
          mon.count = builtins.length monitorHostNames;
          mon.allowMultiplePerNode = false;
          dashboard.enabled = true;
          dashboard.ssl = false;
          network = {
            provider = "host";
            connections.requireMsgr2 = false;
          };
          placement = {
            all = {
              tolerations = [
                { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
              ];
              nodeAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = {
                  nodeSelectorTerms = [
                    {
                      matchExpressions = [
                        {
                          key = "node-group";
                          operator = "In";
                          values = [ "control-plane" ];
                        }
                      ];
                    }
                  ];
                };
              };
            };
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
        };

        cephObjectStores = [
          {
            name = "ceph-objectstore";
            spec = {
              metadataPool.replicated.size = 3;
              dataPool.replicated.size = 3;
              gateway = {
                instances = 1;
                port = 80;
                resources = {
                  limits.memory = "1Gi";
                  requests.cpu = "50m";
                  requests.memory = "64Mi";
                };
              };
            };
            storageClass = {
              enabled = true;
              name = "rook-ceph-objectstore";
              reclaimPolicy = "Delete";
              allowVolumeExpansion = true;
            };
            ingress = {
              enabled = true;
              ingressClassName = "cilium";
              host = {
                name = "objectstore.${domain}";
                path = "/";
              };
              tls = [
                {
                  hosts = [ "objectstore.${domain}" ];
                  secretName = "wildcard-tls";
                }
              ];
              annotations = {
                "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
              };
            };
          }
        ];

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
              parameters = {
                imageFormat = "2";
                imageFeatures = "layering";
                "csi.storage.k8s.io/provisioner-secret-name" = "rook-csi-rbd-provisioner";
                "csi.storage.k8s.io/provisioner-secret-namespace" = namespace;
                "csi.storage.k8s.io/controller-expand-secret-name" = "rook-csi-rbd-provisioner";
                "csi.storage.k8s.io/controller-expand-secret-namespace" = namespace;
                "csi.storage.k8s.io/node-stage-secret-name" = "rook-csi-rbd-node";
                "csi.storage.k8s.io/node-stage-secret-namespace" = namespace;
              };
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
              parameters = {
                "csi.storage.k8s.io/provisioner-secret-name" = "rook-csi-cephfs-provisioner";
                "csi.storage.k8s.io/provisioner-secret-namespace" = namespace;
                "csi.storage.k8s.io/controller-expand-secret-name" = "rook-csi-cephfs-provisioner";
                "csi.storage.k8s.io/controller-expand-secret-namespace" = namespace;
                "csi.storage.k8s.io/node-stage-secret-name" = "rook-csi-cephfs-node";
                "csi.storage.k8s.io/node-stage-secret-namespace" = namespace;
              };
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

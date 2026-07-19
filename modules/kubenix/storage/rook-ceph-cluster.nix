{ lib
, kubenix
, homelab
, ...
}:

let
  namespace = homelab.kubernetes.namespaces.storage;
  inherit (homelab) domain;
  storageNodes = homelab.nodes.group."k8s-storage".configs;
  storageNodesList = lib.mapAttrsToList
    (name: attrs: {
      inherit name;
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
      chart = kubenix.lib.helm.fetch {
        repo = "https://charts.rook.io/release";
        chart = "rook-ceph-cluster";
        version = "1.19.0";
        sha256 = "sha256-GOYYxPe7XWycR8L0pABH8i693nJWzo+9nhFx1UcU9Q8=";
      };
      inherit namespace;
      includeCRDs = true;
      noHooks = false;
      values = {
        toolbox = {
          enabled = true;
          resources = {
            requests.cpu = "50m";
            requests.memory = "64Mi";
          };
        };
        # Ceph 19.2.3's "multiple bdev label" feature (copies at 1/10/100/1000 GiB
        # offsets) makes bluefs-bdev-expand abort when an OSD partition is large
        # enough to cross a label-copy offset (crashes the expand-bluefs init
        # container, so the OSD never starts). Disable multi-label and don't
        # require all label copies to match so OSDs use a single label and the
        # expand step is a safe no-op. Mirrors the live `ceph config set osd ...`.
        configOverride = ''
          [global]
          bluestore_bdev_label_multi = false
          bluestore_bdev_label_require_all = false
        '';
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
                {
                  key = "node-role.kubernetes.io/control-plane";
                  operator = "Exists";
                  effect = "NoSchedule";
                }
              ];
              nodeAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = {
                  nodeSelectorTerms = [
                    {
                      matchExpressions = [
                        {
                          key = "node.kubernetes.io/k8s-storage";
                          operator = "Exists";
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
              limits.memory = "6Gi";
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
          # lab-gamma-wk is an 8Gi node hosting two OSDs. At Ceph's default
          # osd_memory_target (4Gi) the two OSDs alone target ~8Gi, so the node
          # runs into memory-pressure evictions that repeatedly kill low-priority
          # pods (rook-ceph-exporter, node-exporter) and leave evicted husks.
          # Cap the per-host target to 1.5Gi (2 OSDs -> ~3.6Gi actual) so the node
          # keeps ~3Gi of headroom. Only masks gamma's OSDs; the 12-16Gi nodes
          # keep the 4Gi default. Rook reconciles this via `ceph config set`.
          cephConfig = {
            "osd/host:lab-gamma-wk" = {
              osd_memory_target = "1610612736";
            };
          };
          storage = {
            useAllNodes = false;
            useAllDevices = false;
            # Filter to only scan CEPH_OSD_* partlabel devices, prevents ceph-volume from hanging on nbd devices
            deviceFilter = "^(sd[a-z]+[0-9]*|nvme[0-9]+n[0-9]+p?[0-9]*)$";
            nodes = storageNodesList;
          };
        };

        cephObjectStores = [
          {
            name = "ceph-objectstore";
            spec = {
              allowUsersInNamespaces = [ "*" ];
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
              ingressClassName = kubenix.lib.defaultIngressClass;
              host = {
                name = "objectstore.${domain}";
                path = "/";
              };
              tls = [
                {
                  hosts = [ "objectstore.${domain}" ];
                  secretName = kubenix.lib.defaultTLSSecret;
                }
              ];
              annotations = {
                "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
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
              deviceClass = "nvme";
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
                "csi.storage.k8s.io/controller-publish-secret-name" = "rook-csi-rbd-provisioner";
                "csi.storage.k8s.io/controller-publish-secret-namespace" = namespace;
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
              dataPools = [
                {
                  replicated.size = 3;
                }
              ];
              metadataServer = {
                activeCount = 1;
                activeStandby = true;
              };
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
                "csi.storage.k8s.io/controller-publish-secret-name" = "rook-csi-cephfs-provisioner";
                "csi.storage.k8s.io/controller-publish-secret-namespace" = namespace;
                "csi.storage.k8s.io/node-stage-secret-name" = "rook-csi-cephfs-node";
                "csi.storage.k8s.io/node-stage-secret-namespace" = namespace;
              };
            };
          }
        ];

        ingress.dashboard = {
          enabled = true;
          ingressClassName = kubenix.lib.defaultIngressClass;
          host = {
            name = "ceph.${domain}";
            path = "/";
          };
          tls = [
            {
              hosts = [ "ceph.${domain}" ];
              secretName = kubenix.lib.defaultTLSSecret;
            }
          ];
          annotations = {
            "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
          };
        };
      };
    };
  };
}

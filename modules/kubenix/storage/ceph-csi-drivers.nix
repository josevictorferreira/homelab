{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;

  # Pin cephcsi to 3.17.x: 3.18.1 (the ceph-csi-operator 1.1 default) is built
  # for x86-64-v3 and dies on start with "Fatal glibc error: CPU does not
  # support x86-64-v3" on lab-alpha-cp and lab-gamma-wk (Celeron N5105, no
  # AVX2). The pin lives in our own ConfigMap on purpose: Rook 1.21 treats any
  # v3.17 image in its rook-csi-operator-image-set-configmap as a stale 1.20
  # leftover and blanks it on every operator start, and the CSI operator does
  # not watch that ConfigMap, so the DaemonSets silently went back to 3.18.1
  # after a node reboot. Keep until an upstream cephcsi runs on x86-64-v2.
  # v3.17.2 verified to require only x86-64-v2 (GNU property 0x03).
  imageSetName = "ceph-csi-image-set";
  cephcsiImage = "quay.io/cephcsi/cephcsi:v3.17.2";

  # NixOS has no /lib/modules and no FHS binaries, so the CSI node plugins
  # need the booted kernel modules and the host /nix store. The lib-modules
  # entry overrides the operator's built-in volume of the same name (its
  # default mount at /lib/modules stays); host-nix is a new volume + mount.
  nodePluginVolumes = [
    {
      volume = {
        name = "lib-modules";
        hostPath.path = "/run/booted-system/kernel-modules/lib/modules/";
      };
    }
    {
      volume = {
        name = "host-nix";
        hostPath.path = "/nix";
      };
      mount = {
        name = "host-nix";
        mountPath = "/nix";
        readOnly = true;
      };
    }
  ];

  # Sidecars idle at a few millicores; 100m each reserved ~2 CPUs across the
  # four controller pods and starved app scheduling. Set on the Driver CRs too:
  # the operator copies OperatorConfig defaults into each Driver once, so
  # later OperatorConfig changes never reach existing drivers.
  controllerPluginResources = {
    plugin = {
      requests = { cpu = "50m"; memory = "512Mi"; };
      limits.memory = "1Gi";
    };
    provisioner = {
      requests = { cpu = "20m"; memory = "128Mi"; };
      limits.memory = "256Mi";
    };
    attacher = {
      requests = { cpu = "20m"; memory = "128Mi"; };
      limits.memory = "256Mi";
    };
    resizer = {
      requests = { cpu = "20m"; memory = "128Mi"; };
      limits.memory = "256Mi";
    };
    snapshotter = {
      requests = { cpu = "20m"; memory = "128Mi"; };
      limits.memory = "256Mi";
    };
  };

  # Match what Rook 1.19 applied before the CSI settings moved out of the
  # operator: the chart defaults are 30s and "none", which would drop the
  # snapshotter sidecar Velero relies on.
  # nodePlugin.volumes lives here rather than in operatorConfig because the
  # chart's OperatorConfig template mis-indents that list and fails to render.
  # The chart also emits controllerPlugin.replicas per driver, so the
  # OperatorConfig default would not apply.
  driverDefaults = {
    imageSet.name = imageSetName;
    grpcTimeout = 150;
    snapshotPolicy = "volumeSnapshot";
    log.rotation.enabled = false;
    nodePlugin.volumes = nodePluginVolumes;
    controllerPlugin = {
      replicas = 2;
      resources = controllerPluginResources;
    };
  };
in
{
  kubernetes.resources.configMaps.${imageSetName} = {
    metadata = {
      name = imageSetName;
      inherit namespace;
    };
    data.plugin = cephcsiImage;
  };

  kubernetes = {
    # Rook 1.20+ no longer manages CSI driver settings; this chart (from the
    # ceph-csi-operator project, version matching the operator subchart bundled
    # in rook-ceph) owns the OperatorConfig and Driver CRs plus the plugin
    # service accounts and RBAC. Driver names must stay prefixed with the Rook
    # operator namespace to match the StorageClass provisioners.
    helm.releases."ceph-csi-drivers" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://ceph.github.io/ceph-csi-operator";
        chart = "ceph-csi-drivers";
        version = "1.1.0";
        sha256 = "sha256-7zQzYpHrkj8KJpbkBCo5+bTXYsapt30lrujqfFSve6c=";
      };
      inherit namespace;
      values = {
        operatorConfig = {
          inherit namespace;
          driverSpecDefaults = {
            imageSet.name = imageSetName;
            clusterName = namespace;
            log.rotation.enabled = false;
            nodePlugin = {
              priorityClassName = "system-node-critical";
              resources = {
                plugin = {
                  requests = { cpu = "250m"; memory = "512Mi"; };
                  limits.memory = "1Gi";
                };
                registrar = {
                  requests = { cpu = "50m"; memory = "128Mi"; };
                  limits.memory = "256Mi";
                };
              };
            };
            controllerPlugin = {
              priorityClassName = "system-cluster-critical";
              resources = controllerPluginResources;
            };
          };
        };
        drivers = {
          rbd = driverDefaults // {
            enabled = true;
            name = "${namespace}.rbd.csi.ceph.com";
          };
          cephfs = driverDefaults // {
            enabled = true;
            name = "${namespace}.cephfs.csi.ceph.com";
          };
          nfs.enabled = false;
          nvmeof.enabled = false;
        };
      };
    };
  };
}

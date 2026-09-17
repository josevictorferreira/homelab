{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;

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

  # Match what Rook 1.19 applied before the CSI settings moved out of the
  # operator: the chart defaults are 30s and "none", which would drop the
  # snapshotter sidecar Velero relies on.
  # nodePlugin.volumes lives here rather than in operatorConfig because the
  # chart's OperatorConfig template mis-indents that list and fails to render.
  # The chart also emits controllerPlugin.replicas per driver, so the
  # OperatorConfig default would not apply.
  driverDefaults = {
    grpcTimeout = 150;
    snapshotPolicy = "volumeSnapshot";
    log.rotation.enabled = false;
    nodePlugin.volumes = nodePluginVolumes;
    controllerPlugin.replicas = 2;
  };
in
{
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
        version = "1.0.4";
        sha256 = "sha256-mrn2dAjJcAohxpf6HsgOsr4h2q+mnmoIM6uXKRB0dZE=";
      };
      inherit namespace;
      values = {
        operatorConfig = {
          inherit namespace;
          driverSpecDefaults = {
            imageSet.name = "rook-csi-operator-image-set-configmap";
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
              resources = {
                plugin = {
                  requests.memory = "512Mi";
                  limits.memory = "1Gi";
                };
                provisioner = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits.memory = "256Mi";
                };
                attacher = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits.memory = "256Mi";
                };
                resizer = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits.memory = "256Mi";
                };
                snapshotter = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits.memory = "256Mi";
                };
              };
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

{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    helm.releases."rook-ceph-operator" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://charts.rook.io/release";
        chart = "rook-ceph";
        version = "1.19.0";
        sha256 = "sha256-zx3yX4JxoYGKXlDJfTXeRQOM7HgB1BFiWLrgspqCLuk=";
      };
      namespace = namespace;
      includeCRDs = true;
      noHooks = false;
      values = {
        crds.enabled = true;
        csi.cephFSAttachRequired = true;
        csi.csiRBDPluginVolume = [
          {
            name = "lib-modules";
            hostPath = {
              path = "/run/booted-system/kernel-modules/lib/modules/";
            };
          }
          {
            name = "host-nix";
            hostPath = {
              path = "/nix";
            };
          }
        ];
        csi.csiRBDPluginVolumeMount = [
          {
            name = "host-nix";
            mountPath = "/nix";
            readOnly = true;
          }
        ];
        csi.csiCephFSPluginVolume = [
          {
            name = "lib-modules";
            hostPath = {
              path = "/run/booted-system/kernel-modules/lib/modules/";
            };
          }
          {
            name = "host-nix";
            hostPath = {
              path = "/nix";
            };
          }
        ];
        csi.csiCephFSPluginVolumeMount = [
          {
            name = "host-nix";
            mountPath = "/nix";
            readOnly = true;
          }
        ];
      };
    };
  };
}

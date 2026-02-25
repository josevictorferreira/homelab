{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  libModulesVolume = {
    name = "lib-modules";
    hostPath.path = "/run/booted-system/kernel-modules/lib/modules/";
  };

  hostNixVolume = {
    name = "host-nix";
    hostPath.path = "/nix";
  };

  hostNixMount = {
    name = "host-nix";
    mountPath = "/nix";
    readOnly = true;
  };
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
      inherit namespace;
      includeCRDs = true;
      noHooks = false;
      values = {
        crds.enabled = true;
        csi = {
          cephFSAttachRequired = true;
          csiRBDPluginVolume = [ libModulesVolume hostNixVolume ];
          csiRBDPluginVolumeMount = [ hostNixMount ];
          csiCephFSPluginVolume = [ libModulesVolume hostNixVolume ];
          csiCephFSPluginVolumeMount = [ hostNixMount ];
        };
      };
    };
  };
}

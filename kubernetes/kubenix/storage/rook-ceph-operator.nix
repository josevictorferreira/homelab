{ kubenix, ... }:

{
  kubernetes = {
    helm.releases."rook-ceph-operator" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.rook.io/release";
          chart = "rook-ceph";
          version = "1.17.7";
          sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
        };
      namespace = "rook-ceph";
      includeCRDs = true;
      noHooks = true;
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

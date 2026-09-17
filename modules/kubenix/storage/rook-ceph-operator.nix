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
        version = "1.20.7";
        sha256 = "sha256-L/kouXAJXSHs9mSzERceumXpNVJIVRuj5NC1d5uCwR8=";
      };
      inherit namespace;
      includeCRDs = true;
      noHooks = false;
      values = {
        crds.enabled = true;
        # Let OBCs carry a bucket policy (used to grant the rgw-mirror backup
        # user read access to app buckets). Default allowlist is maxObjects,maxSize.
        obcAllowAdditionalConfigFields = "maxObjects,maxSize,bucketPolicy";
        # Rook 1.20 deletes CRUSH rules no pool references once the mgr starts.
        # Keep them: nothing here relies on the cleanup and CRUSH edits are not
        # something to hand to an automatic sweep on this cluster.
        deleteUnusedCrushRules = false;
        # Since Rook 1.20 CSI drivers are configured through the ceph-csi-operator
        # CRs, rendered by the ceph-csi-drivers chart (see ceph-csi-drivers.nix).
      };
    };
  };
}

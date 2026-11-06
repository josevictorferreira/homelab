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
        version = "1.21.2";
        sha256 = "1m3ssbxgq4akfm9hs8nik46nb170apnj32z0zk7x2l059bkw1ha6";
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
        # The cephcsi image pin lives there too: Rook blanks any v3.17 value in
        # its own image-set ConfigMap on start, so csi.cephcsi must stay unset.
      };
    };
  };
}

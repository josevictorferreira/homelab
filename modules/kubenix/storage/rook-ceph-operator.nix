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
        version = "1.21.1";
        sha256 = "sha256-QehfCXPmYingrMbMHJenw1mw1/aPl3PxioKcm8fIecI=";
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
        #
        # Pin cephcsi to 3.17.1. Rook 1.21 leaves the image to the CSI operator
        # default (3.18.1), which is built for x86-64-v3 and dies on start with
        # "Fatal glibc error: CPU does not support x86-64-v3" on lab-alpha-cp and
        # lab-gamma-wk (Celeron N5105, no AVX2). Keep this until an upstream
        # cephcsi image runs on x86-64-v2 again.
        csi.cephcsi = {
          repository = "quay.io/cephcsi/cephcsi";
          tag = "v3.17.1";
        };
      };
    };
  };
}

{ kubenix, homelab, ... }:

let
  immichLibraryPVC = "cephfs-shared-storage-images";
  app = "immich";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/immich-app/immich-charts/immich";
        chart = "immich";
        version = "0.9.3";
        sha256 = "sha256-UHuuu6u+UjHPgdLONZim6j+nyCINtClcAZRRJlHuaaw=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        postgresql.enabled = false;
        redis.enabled = false;
				
				env = [ ];

        envFrom = [
          {
            secretRef = {
              name = "immich-secret";
            };
          }
        ];

        immich = {
          persistence.library.existingClaim = immichLibraryPVC;

          configuration = {
            trash.enabled = true;
            trash.days = 30;
          };

          metrics.enabled = true;
        };

        machine-learning = {
          enabled = true;
          image.repository = "ghcr.io/immich-app/immich-machine-learning";
          image.pullPolicy = "IfNotPresent";

          env.TRANSFORMERS_CACHE = "/cache";

          persistence.cache = {
            enabled = true;
            size = "20Gi";
            type = "pvc";
            accessMode = "ReadWriteOnce";
            storageClass = "rook-ceph-block";
          };
        };

        server = {
          enabled = true;
          image.repository = "ghcr.io/immich-app/immich-server";
          image.pullPolicy = "IfNotPresent";

          ingress.main = {
            enabled = false;
          };
        };
      };
    };
  };
}

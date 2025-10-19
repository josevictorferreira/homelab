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
        version = "0.10.0";
        sha256 = "sha256-BKCFbfRWwXjK3+9F74hgoIO89S2LYaFcnLDLANM2yH8=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
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
          image.tag = "v2.0.0@sha256:68bd95ff703a3b4c6a662b7f638bd2e01e3c7aeb2223dc0f142f02a555e24ca4";
          image.pullPolicy = "IfNotPresent";

          env.TRANSFORMERS_CACHE = "/cache";

          persistence.cache = {
            enabled = true;
            size = "20Gi";
            type = "persistentVolumeClaim";
            accessMode = "ReadWriteOnce";
            storageClass = "rook-ceph-block";
          };
        };

        server = {
          enabled = true;
          image.repository = "ghcr.io/immich-app/immich-server";
          image.tag = "v2.0.0@sha256:d81f4af6a622d0955e5b8e3927da32b3ec882466a7ee8a26906d9cccad4364ca";
          image.pullPolicy = "IfNotPresent";

          service.main = {
            enabled = true;
            type = "LoadBalancer";
            annotations = kubenix.lib.serviceAnnotationFor app;
          };

          ingress.main = {
            enabled = true;
            className = "cilium";
            hosts = [
              {
                host = kubenix.lib.domainFor app;
                paths = [
                  {
                    path = "/";
                    service.name = "immich-server";
                    service.port = 2283;
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = "wildcard-tls";
                hosts = [ (kubenix.lib.domainFor app) ];
              }
            ];
          };
        };
      };
    };
  };
}

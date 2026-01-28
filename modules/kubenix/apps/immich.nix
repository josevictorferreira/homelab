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
        version = "0.10.1";
        sha256 = "sha256-TODO-Get-actual-sha256-for-0.10.1";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        controllers.main.containers.main = {
          env = { };
          envFrom = [
            {
              secretRef = {
                name = "immich-secret";
              };
            }
          ];
        };

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

          controllers.main.containers.main = {
            image.repository = "ghcr.io/immich-app/immich-machine-learning";
            image.tag = "v2.5.0@sha256:TODO-Get-actual-digest-for-v2.5.0";
            image.pullPolicy = "IfNotPresent";
          };

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
          controllers.main.containers.main = {
            image.repository = "ghcr.io/immich-app/immich-server";
            image.tag = "v2.5.0@sha256:TODO-Get-actual-digest-for-v2.5.0";
            image.pullPolicy = "IfNotPresent";
          };

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

{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases."redis" = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://registry-1.docker.io/bitnamicharts/redis";
        chart    = "redis";
        version  = "22.0.7";
        sha256   = "sha256-iJ4clEnUshRP/s/qwkn/07JTSonGzMRV6XpMvwI9pAQ=";
      };
      includeCRDs = true;
      noHooks     = true;
      namespace   = namespace;

      values = {
        architecture = "standalone";

        auth = {
          enabled                       = true;
          existingSecret                = "redis-auth";
          existingSecretPasswordKey     = "redis-password";
        };

        master = {
          persistence = {
            enabled       = true;
            storageClass  = "rook-ceph-block";
            reclaimPolicy = "Retain";
            accessModes   = [ "ReadWriteOnce" ];
            size          = "8Gi";
          };

          service = kubenix.lib.plainServiceFor "redis";
        };

        metrics.enabled = false;
      };
    };
  };
}


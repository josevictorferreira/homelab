{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    registry = "docker.io";
    repository = "bitnamilegacy/redis";
    tag = "8.2.1-debian-12-r0@sha256:25bf63f3caf75af4628c0dfcf39859ad1ac8abe135be85e99699f9637b16dc28";
  };
in
{
  kubernetes = {
    helm.releases."redis" = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://registry-1.docker.io/bitnamicharts/redis";
        chart = "redis";
        version = "22.0.7";
        sha256 = "sha256-aYghmMzdQO5ynmcG6w9aQmzRHnaLMKoNwsjZRKGdbrs=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = image;

        architecture = "standalone";

        auth = {
          enabled = true;
          existingSecret = "redis-auth";
          existingSecretPasswordKey = "redis-password";
        };

        master = {
          persistence = {
            enabled = true;
            storageClass = "rook-ceph-block";
            reclaimPolicy = "Retain";
            accessModes = [ "ReadWriteOnce" ];
            size = "8Gi";
          };

          service = kubenix.lib.plainServiceFor "redis";
        };

        metrics.enabled = false;
      };
    };
  };
}

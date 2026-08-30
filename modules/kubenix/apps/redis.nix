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
      inherit namespace;

      values = {
        inherit image;

        architecture = "standalone";

        auth = {
          enabled = true;
          existingSecret = "redis-auth";
          existingSecretPasswordKey = "redis-password";
        };

        master = {
          persistence = {
            enabled = true;
            storageClass = kubenix.lib.defaultStorageClass;
            reclaimPolicy = "Retain";
            accessModes = [ "ReadWriteOnce" ];
            size = "8Gi";
          };

          service = kubenix.lib.plainServiceFor "redis";

          # Cold boot after an outage: AOF/RDB load on RBD can exceed the
          # chart's 45s liveness budget. startupProbe holds liveness off until
          # Redis has actually loaded; the longer grace lets it persist on exit.
          terminationGracePeriodSeconds = 120;
          startupProbe = {
            enabled = true;
            initialDelaySeconds = 10;
            periodSeconds = 10;
            timeoutSeconds = 5;
            failureThreshold = 30;
          };
        };

        metrics.enabled = false;
      };
    };
  };
}

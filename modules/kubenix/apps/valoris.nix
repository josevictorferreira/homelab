{ homelab, ... }:

let
  imageTag = "latest";
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "valoris-s3";
  secretName = "valoris-config";
in
{
  submodules.instances = {
    valoris = {
      submodule = "release";
      args = {
        namespace = namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-server";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 3000;
        values = {
          defaultPodOptions.imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          controllers.main.containers.main = {
            envFrom = [
              { secretRef.name = secretName; }
              { secretRef.name = "valoris-s3"; }
            ];
          };
        };
      };
    };
    valoris-worker = {
      submodule = "release";
      args = {
        namespace = namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-worker";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 3000;
        values = {
          defaultPodOptions.imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          controllers.main.containers.main = {
            envFrom = [
              { secretRef.name = secretName; }
              { secretRef.name = "valoris-s3"; }
            ];
          };
        };
      };
    };
  };

  kubernetes = {
    resources = {
      objectbucketclaim."valoris-s3" = {
        metadata = {
          namespace = namespace;
        };
        spec = {
          bucketName = bucketName;
          storageClassName = "rook-ceph-objectstore";
        };
      };
    };
  };
}

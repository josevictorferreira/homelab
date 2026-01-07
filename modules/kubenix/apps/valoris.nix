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
          repository = "ghcr.io/josevictorferreira/valoris-frontend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 80;
        command = [ "nginx" "-g" "daemon off;" ];
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
    valoris-backend = {
      submodule = "release";
      args = {
        namespace = namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-backend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 80;
        command = [ "bundle" "exec" "rails" "server" "-p" "80" ];
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
          repository = "ghcr.io/josevictorferreira/valoris-backend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 3000;
        command = [ "bundle" "exec" "bin/jobs" "start" ];
        values = {
          defaultPodOptions.imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
          controllers.main = {
            replicas = 2;
            containers.main = {
              envFrom = [
                { secretRef.name = secretName; }
                { secretRef.name = "valoris-s3"; }
              ];
            };
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

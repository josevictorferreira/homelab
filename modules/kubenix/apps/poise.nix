{ homelab, ... }:

let
  app = "poise";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/poise";
    tag = "latest";
    pullPolicy = "Always";
  };
  port = 3000;
  secretName = "${app}-config";
  bucketName = app;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit
        namespace
        image
        port
        secretName
        ;
      resources = {
        requests = {
          cpu = "100m";
          memory = "512Mi";
        };
        # Solid Queue runs inside Puma (SOLID_QUEUE_IN_PUMA), so the vision and
        # rating jobs — which base64 a whole photo into the request body — share
        # this container's heap with the web workers.
        limits = {
          cpu = "1000m";
          memory = "2Gi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main = {
          envFrom = [
            { secretRef.name = secretName; }
            # Rook writes the bucket credentials here as AWS_ACCESS_KEY_ID /
            # AWS_SECRET_ACCESS_KEY; the S3_* aliases the app reads are mapped
            # below.
            { secretRef.name = "${app}-s3"; }
          ];
          env = [
            {
              name = "S3_ACCESS_KEY_ID";
              valueFrom.secretKeyRef = {
                name = "${app}-s3";
                key = "AWS_ACCESS_KEY_ID";
              };
            }
            {
              name = "S3_SECRET_ACCESS_KEY";
              valueFrom.secretKeyRef = {
                name = "${app}-s3";
                key = "AWS_SECRET_ACCESS_KEY";
              };
            }
          ];
          probes = {
            # db:prepare runs in the entrypoint before Puma binds, so the
            # startup probe has to tolerate a schema load on a cold database.
            startup = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/up";
                  inherit port;
                };
                initialDelaySeconds = 15;
                periodSeconds = 10;
                failureThreshold = 30;
              };
            };
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/up";
                  inherit port;
                };
                periodSeconds = 30;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            };
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/up";
                  inherit port;
                };
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            };
          };
        };
      };
    };
  };

  kubernetes.resources.objectbucketclaim."${app}-s3" = {
    metadata = {
      inherit namespace;
    };
    spec = {
      inherit bucketName;
      storageClassName = "rook-ceph-objectstore";
    };
  };
}

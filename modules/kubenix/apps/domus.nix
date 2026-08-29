{ homelab, kubenix, ... }:

let
  app = "domus";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/domus";
    tag = "latest";
    pullPolicy = "Always";
  };
  port = 3000;
  secretName = "${app}-config";
  # Photos and suggestions: OBC-provisioned RGW bucket. The claim also creates
  # a Secret of the same name with AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
  bucketName = "${app}-s3";
  pullSecrets = [ { name = "ghcr-registry-secret"; } ];
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
          memory = "256Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "1Gi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main = {
          envFrom = [
            { secretRef.name = secretName; }
            # Rook writes AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY here.
            { secretRef.name = bucketName; }
          ];
          env = [
            {
              name = "S3_ACCESS_KEY_ID";
              valueFrom.secretKeyRef = {
                name = bucketName;
                key = "AWS_ACCESS_KEY_ID";
              };
            }
            {
              name = "S3_SECRET_ACCESS_KEY";
              valueFrom.secretKeyRef = {
                name = bucketName;
                key = "AWS_SECRET_ACCESS_KEY";
              };
            }
          ];
        };
        controllers.main.containers.main.probes = {
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

  kubernetes.resources.objectbucketclaim.${bucketName} = {
    metadata = {
      inherit namespace;
    };
    spec = {
      inherit bucketName;
      storageClassName = "rook-ceph-objectstore";
      # imgproxy reads display images straight from the bucket with its own
      # RGW user — the one Rook created for the `valoris-s3` claim it mounts
      # (`kubectl get objectbucket obc-apps-valoris-s3 -o jsonpath='{.spec.additionalState.cephUser}'`);
      # the mirror user needs read for backups.
      additionalConfig.bucketPolicy = builtins.toJSON {
        Version = "2012-10-17";
        Statement = [
          {
            Sid = "domus-readers";
            Effect = "Allow";
            Principal.AWS = [
              "arn:aws:iam:::user/s3-user"
              "arn:aws:iam:::user/obc-apps-valoris-s3-f154e7ba-7bc7-4655-88dd-fd8241ee6416"
            ];
            Action = [
              "s3:ListBucket"
              "s3:GetObject"
            ];
            Resource = [
              "arn:aws:s3:::${bucketName}"
              "arn:aws:s3:::${bucketName}/*"
            ];
          }
        ];
      };
    };
  };
}

{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "linkwarden-files";
in
{
  kubernetes = {
    helm.releases."linkwarden" = {
      chart = kubenix.lib.helm.fetch
        {
          chartUrl = "oci://ghcr.io/fmjstudios/helm/linkwarden";
          chart = "linkwarden";
          version = "0.3.3";
          sha256 = "sha256-rFzutBrDDF4qVj38dYazjv3iUl2uszIJSKWPwrRdX1E=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        image = {
          registry = "ghcr.io";
          repository = "linkwarden/linkwarden";
          tag = "v2.12.2@sha256:c1c6f417ea566de2c2dac6e79353ee5f40cb6a44fd9dd3970c83e6fc098de1df";
        };

        linkwarden = {
          labels = {
            app = "linkwarden";
            release = "linkwarden";
          };
          domain = "linkwarden.${homelab.domain}";

          data = {
            storageType = "s3";
            s3 = {
              bucketName = bucketName;
              endpoint = "http://rook-ceph-rgw-ceph-objectstore.${homelab.kubernetes.namespaces.storage}.svc.cluster.local";
              region = "us-east-1";
              existingSecret = "linkwarden-s3";
            };
          };

          database = {
            existingSecret = "linkwarden-db";
          };
        };

        resources = {
          requests = {
            cpu = "50m";
            memory = "1Gi";
          };
          limits.memory = "1.5Gi";
        };

        service = {
          port = 80;
        };

        postgresql.enabled = false;

        ingress = kubenix.lib.ingressDomainForService "linkwarden";
      };
    };


    resources = {
      deployments.linkwarden = {
        metadata.namespace = namespace;
        spec.template.spec.containers.linkwarden = {
          env = [
            {
              name = "SPACES_KEY";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "linkwarden-s3";
                key = lib.mkForce "AWS_ACCESS_KEY_ID";
              };
            }
            {
              name = "SPACES_SECRET";
              valueFrom.secretKeyRef = {
                name = lib.mkForce "linkwarden-s3";
                key = lib.mkForce "AWS_SECRET_ACCESS_KEY";
              };
            }
            {
              name = "SPACES_FORCE_PATH_STYLE";
              value = "true";
            }
          ];
          envFrom = [
            {
              secretRef.name = "linkwarden-secrets";
            }
          ];
        };
      };

      objectbucketclaim."linkwarden-s3" = {
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

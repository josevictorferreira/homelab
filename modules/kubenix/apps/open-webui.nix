{ kubenix
, homelab
, ...
}:

let
  app = "open-webui";
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "open-webui-files";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.openwebui.com/";
        chart = "open-webui";
        version = "8.1.0";
        sha256 = "sha256-qFG0Iq2IBwkqG6t2Z47GDU3fjftzy3xI7ALNJjctNQk=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;
      values = {
        image = {
          repository = "ghcr.io/open-webui/open-webui";
          tag = "v0.8.12@sha256:8113fa5510020ef05a44afc0c42d33eabeeb2524a996e3e3fb8c437c00f0d792";
          pullPolicy = "IfNotPresent";
        };
        ollama.enabled = false;
        enableOpenaiApi = true;
        openaiBaseApiUrl = "https://openrouter.ai/api/v1";
        ingress = {
          enabled = true;
          host = kubenix.lib.domainFor "openwebui";
          class = "cilium";
          tls = true;
          existingSecret = "wildcard-tls";
        };
        persistence = {
          enabled = true;
          size = "2Gi";
          storageClass = "rook-ceph-block";
          provider = "s3";
          s3 = {
            accessKeyExistingSecret = "open-webui-s3";
            accessKeyExistingAccessKey = "AWS_ACCESS_KEY_ID";
            secretKeyExistingSecret = "open-webui-s3";
            secretKeyExistingSecretKey = "AWS_SECRET_ACCESS_KEY";
            endpointUrl = kubenix.lib.objectStoreEndpoint;
            region = "us-east-1";
            bucket = bucketName;
          };
        };
        websocket.enabled = false;
        pipelines.enabled = false;
        extraEnvFrom = [
          {
            secretRef = {
              name = "open-webui-secrets";
            };
          }
        ];
        extraEnvVars = [
          {
            name = "OPENAI_API_KEY";
            valueFrom = {
              secretKeyRef = {
                name = "open-webui-secrets";
                key = "RAG_OPENAI_API_KEY";
              };
            };
          }
        ];
        resources = {
          requests = {
            cpu = "100m";
            memory = "256Mi";
          };
          limits = {
            cpu = "300m";
            memory = "1Gi";
          };
        };
      };
    };

    resources = {
      objectbucketclaim."open-webui-s3" = {
        metadata = {
          inherit namespace;
        };
        spec = {
          inherit bucketName;
          storageClassName = "rook-ceph-objectstore";
        };
      };
    };

  };
}

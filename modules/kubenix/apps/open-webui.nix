{
  kubenix,
  homelab,
  ...
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
      namespace = namespace;
      values = {
        image = {
          repository = "ghcr.io/open-webui/open-webui";
          tag = "v0.7.2@sha256:16d9a3615b45f14a0c89f7ad7a3bf151f923ed32c2e68f9204eb17d1ce40774b";
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
      };
    };

    resources = {
      objectbucketclaim."open-webui-s3" = {
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

{ lib, kubenix, k8sLib, homelab, ... }:

let
  app = "open-webui";
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "open-webui-files";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch
        {
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
          pullPolicy = "IfNotPresent";
        };
        ollama.enabled = false;
        openaiBaseApiUrls = [
          "https://openrouter.ai/api/v1"
        ];
        ingress = {
          host = k8sLib.domainFor app;
          class = "cilium";
          tls = true;
          existingSecret = "wildcard-tls";
        };
        service = {
          type = "LoadBalancer";
          annotations = k8sLib.serviceIpFor app;
          loadBalancerClass = "cilium";
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
            endpointUrl = k8sLib.objectStoreEndpoint;
            region = "us-east-1";
            bucket = bucketName;
          };
        };
        extraEnvVars = [
          {
            name = "ENABLE_SIGNUP";
            value = "false";
          }
          {
            name = "OPENAI_API_KEY";
            valueFrom = {
              secretKeyRef = {
                name = "openrouter-secrets";
                key = "OPENROUTER_API_KEY";
              };
            };
          }
          {
            name = "OPENAI_API_BASE_URL";
            valueFrom = {
              secretKeyRef = {
                name = "openrouter-secrets";
                key = "OPENROUTER_API_BASE_URL";
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

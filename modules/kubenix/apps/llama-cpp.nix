{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.llama-cpp = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/ggml-org/llama.cpp";
        tag = "server-rocm";
        pullPolicy = "Always";
      };
      port = 8080;
      resources = {
        requests = {
          cpu = "100m";
          memory = "512Mi";
          "amd.com/gpu" = "1";
        };
        limits = {
          cpu = "500m";
          memory = "4Gi";
          "amd.com/gpu" = "1";
        };
      };
      priorityClassName = "preemptible";
      values = {
        service.main.type = "LoadBalancer";
        controllers.main.pod = {
          nodeSelector."node.kubernetes.io/amd-gpu" = "true";
          tolerations = [
            {
              key = "node-role.kubernetes.io/control-plane";
              operator = "Exists";
              effect = "NoSchedule";
            }
          ];
        };
        controllers.main.containers.main = {
          command = [ "/app/llama-server" ];
          args = [
            "--model"
            "/models/bge-reranker-v2-m3-Q4_K_M.gguf"
            "--host"
            "0.0.0.0"
            "--port"
            "8080"
            "--embedding"
            "--pooling"
            "rank"
            "--reranking"
            "--alias"
            "bge-reranker-v2-m3"
          ];
          probes = {
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/health";
                  port = 8080;
                };
                initialDelaySeconds = 60;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            };
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/health";
                  port = 8080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 5;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
            };
            startup = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/health";
                  port = 8080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 60;
              };
            };
          };
        };
        controllers.main.initContainers.download-model = {
          image = {
            repository = "busybox";
            tag = "1.36.1";
          };
          command = [
            "sh"
            "-c"
          ];
          resources = {
            requests = {
              cpu = "50m";
              memory = "64Mi";
            };
            limits = {
              cpu = "200m";
              memory = "128Mi";
            };
          };
          args = [
            ''
              if [ ! -f /models/bge-reranker-v2-m3-Q4_K_M.gguf ]; then
                echo "Downloading bge-reranker-v2-m3 GGUF model..."
                wget -q -O /models/bge-reranker-v2-m3-Q4_K_M.gguf "https://huggingface.co/sinjab/bge-reranker-v2-m3-Q4_K_M-GGUF/resolve/main/bge-reranker-v2-m3-Q4_K_M.gguf"
              fi
            ''
          ];
        };
        persistence.models = {
          enabled = true;
          size = "20Gi";
          type = "persistentVolumeClaim";
          accessMode = "ReadWriteOnce";
          storageClass = kubenix.lib.defaultStorageClass;
          globalMounts = [ { path = "/models"; } ];
        };
        ingress.main = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          hosts = [
            {
              host = kubenix.lib.domainFor "llama-cpp";
              paths = [
                {
                  path = "/";
                  service.name = "llama-cpp";
                  service.port = 8080;
                }
              ];
            }
          ];
          tls = [
            {
              secretName = kubenix.lib.defaultTLSSecret;
              hosts = [ (kubenix.lib.domainFor "llama-cpp") ];
            }
          ];
        };
      };
    };
  };
}

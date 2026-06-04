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
          memory = "64Mi";
        };
        limits = {
          cpu = "500m";
          memory = "4Gi";
        };
      };
      priorityClassName = "preemptible";
      values = {
        service.main.type = "LoadBalancer";
        service.main.ports.embeddings = {
          enabled = true;
          port = 8081;
          targetPort = 8081;
          protocol = "TCP";
        };
        controllers.main.strategy = "Recreate";
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
            "--n-gpu-layers"
            "0"
            "--parallel"
            "1"
            "--fit"
            "off"
            "--batch-size"
            "128"
            "--ubatch-size"
            "128"
            "--no-warmup"
            "--cache-ram"
            "0"
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
        controllers.main.containers.embeddings = {
          image = {
            repository = "ghcr.io/ggml-org/llama.cpp";
            tag = "server-rocm";
            pullPolicy = "Always";
          };
          command = [ "/app/llama-server" ];
          args = [
            "--model"
            "/models/multilingual-e5-large-q4_k_m.gguf"
            "--host"
            "0.0.0.0"
            "--port"
            "8081"
            "--embedding"
            "--alias"
            "intfloat/multilingual-e5-large"
            "--n-gpu-layers"
            "0"
            "--parallel"
            "1"
            "--cache-ram"
            "0"
          ];
          resources = {
            requests = {
              cpu = "50m";
              memory = "64Mi";
            };
            limits = {
              cpu = "500m";
              memory = "2Gi";
            };
          };
          ports = [
            {
              name = "embeddings";
              containerPort = 8081;
              protocol = "TCP";
            }
          ];
          probes = {
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/health";
                  port = 8081;
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
                  port = 8081;
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
                  port = 8081;
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
              if [ ! -f /models/multilingual-e5-large-q4_k_m.gguf ]; then
                echo "Downloading multilingual-e5-large GGUF model..."
                wget -q -O /models/multilingual-e5-large-q4_k_m.gguf "https://huggingface.co/phate334/multilingual-e5-large-gguf/resolve/main/multilingual-e5-large-q4_k_m.gguf"
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

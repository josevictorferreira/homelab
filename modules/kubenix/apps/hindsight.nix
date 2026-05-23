{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  secretName = "hindsight-secrets";
in
{
  submodules.instances = {
    hindsight-api = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/vectorize-io/hindsight-api";
          tag = "latest";
          pullPolicy = "IfNotPresent";
        };
        port = 8888;
        secretName = secretName;
        resources = {
          requests = {
            cpu = "500m";
            memory = "1Gi";
          };
          limits = {
            cpu = "2000m";
            memory = "4Gi";
          };
        };
        priorityClassName = "preemptible";
        values = {
          service.main.type = "ClusterIP";
          controllers.main.containers.main = {
            env = {
              HINDSIGHT_API_VECTOR_EXTENSION = "vchord";
              HINDSIGHT_API_TEXT_SEARCH_EXTENSION = "native";
              HINDSIGHT_API_PORT = "8888";
              HINDSIGHT_API_HOST = "0.0.0.0";
              HINDSIGHT_API_LLM_PROVIDER = "openai";
              HINDSIGHT_API_LLM_MODEL = "cheap-nitro";
              HINDSIGHT_API_LLM_BASE_URL = "https://router9.josevictor.me/v1";
              HINDSIGHT_API_REFLECT_LLM_MODEL = "cheap-fast";
              HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openai";
              HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL = "openrouter/nvidia/llama-nemotron-embed-vl-1b-v2:free";
              HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL = "https://router9.josevictor.me/v1";
              HINDSIGHT_API_RERANKER_PROVIDER = "local";
              HINDSIGHT_API_RERANKER_LOCAL_MODEL = "cross-encoder/ms-marco-MiniLM-L-6-v2";
              HINDSIGHT_API_WORKER_MAX_SLOTS = "8";
              HINDSIGHT_API_WORKER_CONSOLIDATION_MAX_SLOTS = "2";
              HINDSIGHT_API_LLM_TIMEOUT = "30";
              HINDSIGHT_API_LLM_MAX_RETRIES = "1";
              HINDSIGHT_API_LLM_MAX_CONCURRENT = "8";
              HINDSIGHT_API_RETAIN_LLM_TIMEOUT = "30";
              HINDSIGHT_API_RETAIN_LLM_MAX_RETRIES = "1";
              HINDSIGHT_API_CONSOLIDATION_LLM_TIMEOUT = "45";
              HINDSIGHT_API_CONSOLIDATION_LLM_MAX_RETRIES = "1";
            };
            probes = {
              liveness = {
                enabled = true;
                custom = true;
                spec = {
                  httpGet = {
                    path = "/health";
                    port = 8888;
                  };
                  initialDelaySeconds = 30;
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
                    port = 8888;
                  };
                  initialDelaySeconds = 10;
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
                    port = 8888;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 18;
                };
              };
            };
          };
        };
      };
    };

    hindsight-cp = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/vectorize-io/hindsight-control-plane";
          tag = "latest";
          pullPolicy = "IfNotPresent";
        };
        port = 3000;
        secretName = secretName;
        resources = {
          requests = {
            cpu = "250m";
            memory = "512Mi";
          };
          limits = {
            cpu = "1000m";
            memory = "2Gi";
          };
        };
        priorityClassName = "preemptible";
        values = {
          service.main.type = "ClusterIP";
          controllers.main.containers.main = {
            env = {
              HINDSIGHT_CP_DATAPLANE_API_URL = "http://hindsight-api:8888";
              NODE_ENV = "production";
              HINDSIGHT_CP_HOSTNAME = "0.0.0.0";
              HINDSIGHT_CP_PORT = "3000";
            };
            probes = {
              liveness = {
                enabled = true;
                custom = true;
                spec = {
                  tcpSocket = {
                    port = 3000;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
              };
              readiness = {
                enabled = true;
                custom = true;
                spec = {
                  tcpSocket = {
                    port = 3000;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
              };
            };
          };
          ingress.main = {
            enabled = true;
            className = kubenix.lib.defaultIngressClass;
            annotations = {
              "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
            };
            hosts = [
              {
                host = kubenix.lib.domainFor "hindsight";
                paths = [
                  {
                    path = "/";
                    service.name = "hindsight-cp";
                    service.port = 3000;
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = kubenix.lib.defaultTLSSecret;
                hosts = [ (kubenix.lib.domainFor "hindsight") ];
              }
            ];
          };
        };
      };
    };
  };
}

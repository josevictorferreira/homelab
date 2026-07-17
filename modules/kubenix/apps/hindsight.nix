{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  secretName = "hindsight-secrets";
  apiImage = {
    repository = "ghcr.io/vectorize-io/hindsight-api";
    tag = "0.8.3@sha256:dbf686c87ce8d541eb668c49184549fe94bf928c15c31cedba005c86a425d147";
    pullPolicy = "IfNotPresent";
  };
  apiImageRef = "${apiImage.repository}:${apiImage.tag}";
in
{
  submodules.instances = {
    hindsight-api = {
      submodule = "release";
      args = {
        inherit namespace;
        image = apiImage;
        port = 8888;
        secretName = secretName;
        resources = {
          requests = {
            cpu = "50m";
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
              HINDSIGHT_API_VECTOR_EXTENSION = "pgvector";
              HINDSIGHT_API_TEXT_SEARCH_EXTENSION = "native";
              HINDSIGHT_API_TEXT_SEARCH_EXTENSION_NATIVE_LANGUAGE = "portuguese";
              HINDSIGHT_API_PORT = "8888";
              HINDSIGHT_API_HOST = "0.0.0.0";
              HINDSIGHT_API_LLM_PROVIDER = "openai";
              HINDSIGHT_API_LLM_MODEL = "pippin";
              HINDSIGHT_API_LLM_BASE_URL = "https://omniroute.josevictor.me/v1";
              HINDSIGHT_API_REFLECT_LLM_MODEL = "haldir";
              HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openai";
              HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL = "https://openrouter.ai/api/v1";
              HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL = "intfloat/multilingual-e5-large";
              HINDSIGHT_API_RERANKER_PROVIDER = "siliconflow";
              HINDSIGHT_API_RERANKER_SILICONFLOW_MODEL = "Qwen/Qwen3-Reranker-0.6B";
              HINDSIGHT_API_RERANKER_SILICONFLOW_TIMEOUT = "60";
              HINDSIGHT_API_RERANKER_SILICONFLOW_BASE_URL = "https://api.siliconflow.com/v1";
              HINDSIGHT_API_RERANKER_MAX_CANDIDATES = "32";
              HINDSIGHT_API_WORKER_MAX_SLOTS = "8";
              HINDSIGHT_API_WORKER_CONSOLIDATION_MAX_SLOTS = "2";
              HINDSIGHT_API_LLM_TIMEOUT = "120";
              HINDSIGHT_API_LLM_MAX_RETRIES = "2";
              # Cap concurrent LLM calls to omniroute (#5152): 8 parallel large bodies
              # through pippin stacked enough compression-pipeline heap to OOM omniroute.
              # Defense-in-depth alongside omniroute's compression concurrency gate.
              HINDSIGHT_API_LLM_MAX_CONCURRENT = "2";
              HINDSIGHT_API_RETAIN_LLM_TIMEOUT = "120";
              HINDSIGHT_API_RETAIN_LLM_MAX_RETRIES = "2";
              HINDSIGHT_API_CONSOLIDATION_LLM_TIMEOUT = "120";
              HINDSIGHT_API_CONSOLIDATION_LLM_MAX_RETRIES = "2";
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
                  failureThreshold = 60;
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
          tag = "0.8.3@sha256:a2972501df6f6c2e2c41700e019553285dcd64180cc1c3f75a44a3b77a339e2e";
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

  # Reaper: reset async_operations stuck in "processing" because their
  # hindsight-api worker pod no longer exists. The poller serialises
  # consolidation per bank, so a dead worker can permanently block a bank.
  kubernetes.resources.serviceAccounts."hindsight-reaper" = {
    metadata = {
      name = "hindsight-reaper";
      inherit namespace;
    };
  };

  kubernetes.resources.roles."hindsight-reaper" = {
    metadata = {
      name = "hindsight-reaper";
      inherit namespace;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [ "pods" ];
        verbs = [
          "get"
          "list"
        ];
      }
    ];
  };

  kubernetes.resources.roleBindings."hindsight-reaper" = {
    metadata = {
      name = "hindsight-reaper";
      inherit namespace;
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "hindsight-reaper";
        inherit namespace;
      }
    ];
    roleRef = {
      kind = "Role";
      name = "hindsight-reaper";
      apiGroup = "rbac.authorization.k8s.io";
    };
  };

  kubernetes.resources.cronJobs."hindsight-reaper" = {
    metadata = {
      name = "hindsight-reaper";
      inherit namespace;
    };
    spec = {
      schedule = "*/10 * * * *";
      concurrencyPolicy = "Forbid";
      jobTemplate.spec.template.spec = {
        serviceAccountName = "hindsight-reaper";
        restartPolicy = "OnFailure";
        containers = [
          {
            name = "hindsight-reaper";
            image = apiImageRef;
            imagePullPolicy = "IfNotPresent";
            envFrom = [ { secretRef.name = "hindsight-secrets"; } ];
            env = [
              {
                name = "HINDSIGHT_REAPER_STALE_MINUTES";
                value = "5";
              }
            ];
            command = [
              "python3"
              "-c"
              ''
                import json
                import os
                import ssl
                import sys
                import urllib.request
                from datetime import datetime, timedelta, timezone

                import sqlalchemy as sa
                from sqlalchemy import text

                TOKEN_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/token'
                CA_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
                NAMESPACE_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'

                STALE_MINUTES = int(os.environ.get('HINDSIGHT_REAPER_STALE_MINUTES', '5'))
                DB_URL = os.environ['HINDSIGHT_API_DATABASE_URL']


                def live_hindsight_api_pods():
                    host = os.environ['KUBERNETES_SERVICE_HOST']
                    port = os.environ['KUBERNETES_SERVICE_PORT']
                    namespace = open(NAMESPACE_PATH).read().strip()
                    token = open(TOKEN_PATH).read().strip()
                    url = (
                        f'https://{host}:{port}/api/v1/namespaces/{namespace}/pods'
                        '?labelSelector=app.kubernetes.io%2Fname%3Dhindsight-api'
                    )
                    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
                    ctx = ssl.create_default_context(cafile=CA_PATH)
                    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                        data = json.loads(resp.read().decode())
                    return {item['metadata']['name'] for item in data.get('items', [])}


                def main():
                    live = live_hindsight_api_pods()
                    print(f'live hindsight-api pods: {sorted(live)}')

                    if not live:
                        print('no live hindsight-api pods; skipping reset')
                        return

                    engine = sa.create_engine(DB_URL)
                    with engine.begin() as conn:
                        result = conn.execute(
                            text("""
                                SELECT operation_id, bank_id, operation_type, worker_id, updated_at
                                FROM async_operations
                                WHERE status = 'processing'
                                  AND worker_id LIKE 'hindsight-api-%'
                                  AND worker_id NOT IN :live
                                  AND updated_at < now() - interval '1 minute' * :stale
                                ORDER BY updated_at
                            """),
                            {
                                'live': tuple(live),
                                'stale': STALE_MINUTES,
                            },
                        )
                        rows = result.mappings().fetchall()

                        if not rows:
                            print('no stale processing operations found')
                            return

                        print(f'resetting {len(rows)} stale operation(s):')
                        for row in rows:
                            print(
                                f"  {row['operation_id']} {row['bank_id']}"
                                f" {row['operation_type']} {row['worker_id']}"
                                f" {row['updated_at']}"
                            )

                        ids = [row['operation_id'] for row in rows]
                        update = conn.execute(
                            text("""
                                UPDATE async_operations
                                SET status = 'pending',
                                    worker_id = NULL,
                                    claimed_at = NULL,
                                    retry_count = 0,
                                    next_retry_at = NULL,
                                    updated_at = now()
                                WHERE operation_id = ANY(:ids)
                                  AND status = 'processing'
                            """),
                            {'ids': ids},
                        )
                        print(f'reset {update.rowcount} operation(s) to pending')


                if __name__ == '__main__':
                    try:
                        main()
                    except Exception as e:
                        print(f'error: {e}', file=sys.stderr)
                        sys.exit(1)
              ''
            ];
            resources = {
              requests = {
                # apps namespace LimitRange enforces min 50m CPU/container;
                # 10m was silently rejected (FailedCreate), so the reaper never ran.
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "100m";
                memory = "128Mi";
              };
            };
          }
        ];
      };
    };
  };
}

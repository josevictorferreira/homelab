{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # RBAC: full cluster access for OpenClaw-Nix pod
  kubernetes.resources.serviceAccounts.openclaw-nix = {
    metadata.namespace = namespace;
  };

  kubernetes.resources.clusterRoles.openclaw-nix-cluster-admin = {
    metadata = { };
    rules = [
      {
        apiGroups = [ "*" ];
        resources = [ "*" ];
        verbs = [ "*" ];
      }
      {
        nonResourceURLs = [ "*" ];
        verbs = [ "*" ];
      }
    ];
  };

  kubernetes.resources.clusterRoleBindings.openclaw-nix-cluster-admin = {
    metadata = { };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "openclaw-nix-cluster-admin";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "openclaw-nix";
        inherit namespace;
      }
    ];
  };

  submodules.instances.openclaw-nix = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/openclaw-nix";
        tag = "latest";
        pullPolicy = "Always";
      };
      port = 18789;
      replicas = 1;
      secretName = "openclaw-secrets";

      # Config template mounted at /etc/openclaw/config-template.json
      # The image entrypoint copies it to /config/openclaw.json and substitutes env vars
      config = {
        filename = "config-template.json";
        mountPath = "/etc/openclaw";
        data = {
          agents = {
            list = [
              {
                id = "main";
                identity = {
                  name = "Mel";
                  theme = "minha fiel assistente";
                  emoji = "🐕";
                };
              }
            ];
            defaults = {
              workspace = "/home/node/.openclaw/workspace";
              model = {
                primary = "kimi-coding/k2p5";
              };
              userTimezone = "America/Sao_Paulo";
              timeoutSeconds = 600;
              memorySearch = {
                provider = "gemini";
                model = "gemini-embedding-001";
              };
            };
          };
          session = {
            scope = "per-sender";
            reset = {
              mode = "daily";
              atHour = 4;
            };
            idleMinutes = 60;
          };
          tools = {
            allow = [
              "exec"
              "read"
              "write"
              "edit"
              "process"
              "web_search"
              "web_fetch"
              "canvas"
              "nodes"
              "message"
              "cron"
              "gateway"
              "browser"
              "sessions_list"
              "sessions_history"
              "sessions_send"
              "sessions_spawn"
              "session_status"
              "agents_list"
            ];
            deny = [ ];
            web = {
              search = {
                provider = "perplexity";
                perplexity = {
                  baseUrl = "https://openrouter.ai/api/v1";
                  model = "perplexity/sonar-pro";
                  apiKey = "\${OPENROUTER_API_KEY}";
                };
              };
            };
          };
          messages = {
            tts = {
              auto = "always";
              provider = "elevenlabs";
              summaryModel = "google/gemini-2.0-flash";
              elevenlabs = {
                apiKey = "\${ELEVENLABS_API_KEY}";
                voiceId = "GOkMqfyKMLVUcYfO2WbB";
                modelId = "eleven_multilingual_v2";
                seed = 91;
                voiceSettings = {
                  stability = 0.5;
                  similarityBoost = 0.75;
                  style = 0.0;
                  useSpeakerBoost = true;
                  speed = 1.0;
                };
              };
            };
          };
          plugins = {
            allow = [
              "matrix"
              "whatsapp"
            ];
          };
          gateway = {
            mode = "local";
            port = 18789;
            bind = "lan";
          };
          logging = {
            level = "debug";
          };
          channels = {
            matrix = {
              enabled = true;
              homeserver = "http://synapse-matrix-synapse:8008";
              accessToken = "\${OPENCLAW_MATRIX_TOKEN}";
              userId = "@openclaw:josevictor.me";
              encryption = false;
              dm = {
                policy = "allowlist";
                allowFrom = [
                  "@jose:josevictor.me"
                  "@admin:josevictor.me"
                  "@zeh:josevictor.me"
                ];
              };
              autoJoin = "allowlist";
              autoJoinAllowList = [
                "@jose:josevictor.me"
                "@admin:josevictor.me"
                "@zeh:josevictor.me"
              ];
              mediaMaxMb = 150;
              groupPolicy = "disabled";
            };
            whatsapp = {
              dmPolicy = "allowlist";
              allowFrom = [
                "\${WHATSAPP_NUMBER}"
              ];
              groupPolicy = "allowlist";
              groupAllowFrom = [ "\${WHATSAPP_NUMBER}" ];
              ackReaction = {
                emoji = "👀";
                direct = true;
                group = "mentions";
              };
            };
          };
          env = {
            MOONSHOT_API_KEY = "\${MOONSHOT_API_KEY}";
            ELEVENLABS_API_KEY = "\${ELEVENLABS_API_KEY}";
            OPENROUTER_API_KEY = "\${OPENCLAW_MATRIX_TOKEN}";
          };
          models = {
            mode = "merge";
            providers = {
              kimi-coding = {
                baseUrl = "https://api.kimi.com/coding";
                apiKey = "\${MOONSHOT_API_KEY}";
                api = "anthropic-messages";
                models = [
                  {
                    id = "k2p5";
                    name = "Kimi K2.5";
                    reasoning = false;
                    input = [ "text" ];
                    contextWindow = 256000;
                    maxTokens = 8192;
                  }
                ];
              };
            };
          };
        };
      };

      # Main persistence: use default (disabled) — custom volumes via values
      values = {
        # Disable ingress (internal service only)
        ingress.main.enabled = false;

        # Override service type to ClusterIP (release default is LoadBalancer)
        service.main.type = "ClusterIP";

        # Security context: run as root for full access
        controllers.main.containers.main.securityContext = {
          runAsUser = 0;
          runAsGroup = 0;
        };

        # Service account for cluster-admin RBAC
        controllers.main.serviceAccount.name = "openclaw-nix";
        defaultPodOptions.automountServiceAccountToken = true;

        # DNS config: cluster DNS + Tailscale MagicDNS
        controllers.main.pod.dnsPolicy = "None";
        controllers.main.pod.dnsConfig = {
          nameservers = [
            "10.43.0.10"
            "100.100.100.100"
          ];
          searches = [
            "apps.svc.cluster.local"
            "svc.cluster.local"
            "cluster.local"
          ];
          options = [
            {
              name = "ndots";
              value = "5";
            }
          ];
        };

        # Environment overrides
        controllers.main.containers.main.env.OPENCLAW_CONFIG_PATH = "/config/openclaw.json";
        controllers.main.containers.main.env.OPENCLAW_DATA_DIR = "/state/openclaw";
        controllers.main.containers.main.env.HOME = "/state/home";
        controllers.main.containers.main.env.TZ = "America/Sao_Paulo";

        # Secret env refs
        controllers.main.containers.main.env.GEMINI_API_KEY = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "GEMINI_API_KEY";
          };
        };
        controllers.main.containers.main.env.OPENROUTER_API_KEY = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "OPENROUTER_API_KEY";
          };
        };
        controllers.main.containers.main.env.MINIMAX_API_KEY = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "MINIMAX_API_KEY";
          };
        };
        controllers.main.containers.main.env.KIMI_API_KEY = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "KIMI_API_KEY";
          };
        };
        controllers.main.containers.main.env.OPENCLAW_MATRIX_TOKEN = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "OPENCLAW_MATRIX_TOKEN";
          };
        };
        controllers.main.containers.main.env.ELEVENLABS_API_KEY = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "ELEVENLABS_API_KEY";
          };
        };
        controllers.main.containers.main.env.GITHUB_TOKEN = {
          valueFrom.secretKeyRef = {
            name = "openclaw-secrets";
            key = "GITHUB_TOKEN";
          };
        };

        # Tailscale sidecar
        controllers.main.containers.tailscale = {
          image = {
            repository = "tailscale/tailscale";
            tag = "latest";
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
            capabilities.add = [
              "NET_ADMIN"
              "NET_RAW"
            ];
          };
          env = {
            TS_AUTHKEY = {
              valueFrom.secretKeyRef = {
                name = "openclaw-secrets";
                key = "TS_AUTHKEY";
              };
            };
            TS_HOSTNAME = "openclaw-nix";
            TS_USERSPACE = "false";
            TS_STATE_DIR = "/var/lib/tailscale";
            TS_ACCEPT_DNS = "false";
            TS_AUTH_ONCE = "true";
            TS_KUBE_SECRET = "";
          };
        };

        # Persistence: writable config scratch dir (main container only)
        persistence.scratch-config = {
          type = "emptyDir";
          advancedMounts.main.main = [ { path = "/config"; } ];
        };

        # Persistence: state (block storage, main container only)
        persistence.state = {
          type = "persistentVolumeClaim";
          storageClass = "rook-ceph-block";
          size = "10Gi";
          accessMode = "ReadWriteOnce";
          advancedMounts.main.main = [ { path = "/state"; } ];
        };

        # Persistence: logs (block storage, main container only)
        persistence.logs = {
          type = "persistentVolumeClaim";
          storageClass = "rook-ceph-block";
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          advancedMounts.main.main = [ { path = "/logs"; } ];
        };

        # Persistence: workspace on CephFS shared storage
        persistence.workspace = {
          type = "persistentVolumeClaim";
          existingClaim = "cephfs-shared-storage-root";
          advancedMounts.main.main = [
            {
              path = "/home/node/.openclaw/workspace";
              subPath = "openclaw";
            }
          ];
        };

        # Persistence: tailscale state (block storage)
        persistence.tailscale-state = {
          type = "persistentVolumeClaim";
          storageClass = "rook-ceph-block";
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
        };

        # Persistence: /dev/net/tun for tailscale
        persistence.dev-tun = {
          type = "hostPath";
          hostPath = "/dev/net/tun";
          advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
        };
      };
    };
  };
}

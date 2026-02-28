{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # RBAC: full cluster access for OpenClaw-Nix pod
  kubernetes.resources = {
    serviceAccounts.openclaw-nix = {
      metadata.namespace = namespace;
    };

    clusterRoles.openclaw-nix-cluster-admin = {
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

    clusterRoleBindings.openclaw-nix-cluster-admin = {
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
  };

  submodules.instances.openclaw-nix = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/openclaw-nix";
        tag = "v2026.2.26";
        pullPolicy = "Always";
      };
      port = 18789;
      replicas = 1;
      secretName = "openclaw-config";

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
                fallbacks = [
                  "zai-coding-plan/glm-5"
                  "minimax/MiniMax-M2.5"
                ];
              };
              userTimezone = "America/Sao_Paulo";
              timeoutSeconds = 600;
              imageModel = {
                primary = "github-copilot/gemini-3-flash-preview";
                fallbacks = [ "kimi-coding/k2p5" ];
              };
              contextPruning = {
                mode = "cache-ttl";
                ttl = "30m";
              };
              memorySearch = {
                provider = "gemini";
                model = "gemini-embedding-001";
              };
              compaction = {
                reserveTokensFloor = 20000;
                memoryFlush = {
                  enabled = true;
                  softThresholdTokens = 4000;
                  systemPrompt = "Session nearing compaction. Store durable memories now.";
                  prompt = "Write any lasting notes to memory/YYYY-MM-DD.md; reply with NO_REPLY if nothing to store.";
                };
              };
              subagents = {
                model = "minimax/MiniMax-M2.5";
                maxConcurrent = 4;
                runTimeoutSeconds = 900;
                archiveAfterMinutes = 60;
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
            media = {
              concurrency = 2;
              audio = {
                enabled = true;
                maxBytes = 20971520;
                scope = {
                  default = "deny";
                  rules = [
                    {
                      action = "allow";
                      match = {
                        chatType = "direct";
                      };
                    }
                  ];
                };
                models = [
                  {
                    provider = "elevenlabs";
                    model = "scribe_v2";
                  }
                ];
              };
              video = {
                enabled = true;
                maxBytes = 52428800;
                models = [
                  {
                    provider = "github-copilot";
                    model = "gemini-3-flash-preview";
                  }
                ];
              };
            };
          };
          messages = {
            tts = {
              auto = "inbound";
              provider = "elevenlabs";
              summaryModel = "kimi-coding/k2p5";
              elevenlabs = {
                apiKey = "\${ELEVENLABS_API_KEY}";
                voiceId = "GOkMqfyKMLVUcYfO2WbB";
                modelId = "eleven_v3";
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
              "memory-core"
            ];
            slots.memory = "memory-core";
          };
          gateway = {
            mode = "local";
            port = 18789;
            bind = "lan";
            controlUi = {
              dangerouslyAllowHostHeaderOriginFallback = true;
            };
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
              enabled = true;
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
              zai-coding-plan = {
                baseUrl = "https://api.z.ai/api/anthropic";
                apiKey = "\${Z_AI_API_KEY}";
                api = "anthropic-messages";
                models = [
                  {
                    id = "glm-5";
                    name = "GLM-5";
                    reasoning = true;
                    input = [ "text" ];
                    contextWindow = 120000;
                    maxTokens = 8192;
                  }
                ];
              };
              minimax = {
                baseUrl = "https://api.minimaxi.com/anthropic";
                apiKey = "\${MINIMAX_API_KEY}";
                api = "anthropic-messages";
                models = [
                  {
                    id = "MiniMax-M2.5";
                    name = "MiniMax M2.5";
                    reasoning = true;
                    input = [ "text" ];
                    cost = {
                      input = 15;
                      output = 60;
                      cacheRead = 2;
                      cacheWrite = 10;
                    };
                    contextWindow = 200000;
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
        # Enable ingress for external access
        ingress.main = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          hosts = [
            {
              host = "openclaw.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  service.name = "openclaw-nix";
                  service.port = 18789;
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [
                "openclaw.${homelab.domain}"
              ];
              secretName = "wildcard-tls";
            }
          ];
        };

        # Override service type to ClusterIP (release default is LoadBalancer)
        service.main.type = "ClusterIP";

        defaultPodOptions.automountServiceAccountToken = true;
        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];

        # Security context: run as root for full access
        controllers.main = {
          containers.main = {
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
            };

            env = {
              OPENCLAW_CONFIG_PATH = "/config/openclaw.json";
              OPENCLAW_DATA_DIR = "/home/node/.openclaw";
              OPENCLAW_STATE_DIR = "/home/node/.openclaw";
              HOME = "/state/home";
              TZ = "America/Sao_Paulo";
              NODE_PATH = "/lib/openclaw/extensions/matrix/node_modules";

              # Secret env refs
              GEMINI_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "GEMINI_API_KEY";
                };
              };
              OPENROUTER_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "OPENROUTER_API_KEY";
                };
              };
              Z_AI_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "Z_AI_API_KEY";
                };
              };
              COPILOT_GITHUB_TOKEN = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "COPILOT_GITHUB_TOKEN";
                };
              };
              MINIMAX_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "MINIMAX_API_KEY";
                };
              };
              KIMI_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "KIMI_API_KEY";
                };
              };
              OPENCLAW_MATRIX_TOKEN = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "OPENCLAW_MATRIX_TOKEN";
                };
              };
              ELEVENLABS_API_KEY = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "ELEVENLABS_API_KEY";
                };
              };
              GITHUB_TOKEN = {
                valueFrom.secretKeyRef = {
                  name = "openclaw-config";
                  key = "GITHUB_TOKEN";
                };
              };
            };

            # Command: install matrix deps then start gateway
            command = [
              "bash"
              "-c"
              ''
                set -e
                echo "Installing matrix plugin dependencies..."

                # Find the actual nix store path where the gateway loads extensions from
                # (resolves symlinks to get the real path)
                MATRIX_EXT=$(readlink -f /lib/openclaw/extensions/matrix 2>/dev/null || echo "/lib/openclaw/extensions/matrix")

                if [ -d "$MATRIX_EXT" ]; then
                  echo "Found matrix extension at: $MATRIX_EXT"
                  cd "$MATRIX_EXT"

                  # Check if node_modules exists and has @vector-im/matrix-bot-sdk
                  if [ ! -d "node_modules/@vector-im" ]; then
                    echo "Installing npm dependencies..."
                    # Strip workspace: protocol deps that npm can't handle
                    node -e "
                      const fs = require('fs');
                      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
                      delete pkg.devDependencies;
                      fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
                    "
                    npm install --omit=dev --no-package-lock --legacy-peer-deps 2>&1 || echo "WARN: npm install failed"
                    echo "Matrix plugin dependencies installed"
                  else
                    echo "node_modules already exists with deps, skipping"
                  fi
                else
                  echo "Matrix extension not found at $MATRIX_EXT"
                fi

                echo "Starting openclaw gateway..."
                # Run the entrypoint script which handles config generation and starts the gateway
                exec /entrypoint.sh
              ''
            ];
          };

          # Tailscale sidecar
          containers.tailscale = {
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
                  name = "openclaw-config";
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

          # Service account for cluster-admin RBAC
          serviceAccount.name = "openclaw-nix";

          # DNS config: cluster DNS + Tailscale MagicDNS
          pod = {
            dnsPolicy = "None";
            dnsConfig = {
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
          };
        };

        persistence = {
          scratch-config = {
            type = "emptyDir";
            advancedMounts.main.main = [ { path = "/config"; } ];
          };

          # Persistence: state (block storage, main container only)
          state = {
            type = "persistentVolumeClaim";
            storageClass = "rook-ceph-block";
            size = "10Gi";
            accessMode = "ReadWriteOnce";
            advancedMounts.main.main = [ { path = "/state"; } ];
          };

          # Persistence: logs (block storage, main container only)
          logs = {
            type = "persistentVolumeClaim";
            storageClass = "rook-ceph-block";
            size = "1Gi";
            accessMode = "ReadWriteOnce";
            advancedMounts.main.main = [ { path = "/logs"; } ];
          };

          # Persistence: CephFS shared storage — single PVC, two mounts
          # Full shared at /home/node/shared, openclaw subdir at ~/.openclaw
          shared-storage = {
            type = "persistentVolumeClaim";
            existingClaim = "cephfs-shared-storage-root";
            advancedMounts.main.main = [
              { path = "/home/node/shared"; }
              {
                path = "/home/node/.openclaw";
                subPath = "openclaw";
              }
            ];
          };

          # Persistence: tailscale state (block storage)
          tailscale-state = {
            type = "persistentVolumeClaim";
            storageClass = "rook-ceph-block";
            size = "1Gi";
            accessMode = "ReadWriteOnce";
            advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
          };

          # Persistence: /dev/net/tun for tailscale
          dev-tun = {
            type = "hostPath";
            hostPath = "/dev/net/tun";
            advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
          };
        };
      };
    };
  };
}

{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # RBAC: full cluster access for OpenClaw pod
  kubernetes.resources.serviceAccounts.openclaw = {
    metadata.namespace = namespace;
  };

  kubernetes.resources.clusterRoles.openclaw-cluster-admin = {
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

  kubernetes.resources.clusterRoleBindings.openclaw-cluster-admin = {
    metadata = { };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "openclaw-cluster-admin";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "openclaw";
        inherit namespace;
      }
    ];
  };

  submodules.instances.openclaw = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/openclaw/openclaw";
        tag = "2026.2.19@sha256:5352d3ababbc12237fda60fe00a25237441eb7bb5e3d3062a6b0b5fbd938734d";
        pullPolicy = "IfNotPresent";
      };
      port = 18789;
      replicas = 1;
      secretName = "openclaw-secrets";
      command = [
        "sh"
        "-c"
        ''
          echo "Installing matrix plugin deps into extension dir..."
          cd /app/extensions/matrix
          # Strip workspace: protocol deps that npm can't handle, using node for valid JSON
          node -e "
            const fs = require('fs');
            const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
            delete pkg.devDependencies;
            fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
          "
          npm install --omit=dev --no-package-lock --legacy-peer-deps 2>&1 || echo "WARN: npm install in extension dir failed"
          echo "Ensuring matrix plugin is enabled in config..."
          cd /app
          node -e "
            const fs = require('fs');
            const cfgPath = '/home/node/.openclaw/openclaw.json';
            let raw = fs.readFileSync(cfgPath, 'utf8');
            // Substitute known env var placeholders
            const vars = [
              'OPENCLAW_MATRIX_TOKEN', 'ELEVENLABS_API_KEY', 'MOONSHOT_API_KEY',
              'OPENROUTER_API_KEY', 'WHATSAPP_NUMBER', 'WHATSAPP_BOT_NUMBER'
            ];
            vars.forEach(name => {
              const val = process.env[name];
              if (val) {
                raw = raw.split('\x24{' + name + '}').join(val);
                console.log('Substituted:', name);
              }
            });
            const cfg = JSON.parse(raw);
            if (!cfg.plugins) cfg.plugins = {};
            if (!cfg.plugins.entries) cfg.plugins.entries = {};
            if (!cfg.plugins.entries.matrix) cfg.plugins.entries.matrix = {};
            cfg.plugins.entries.matrix.enabled = true;
            if (!cfg.plugins.entries.whatsapp) cfg.plugins.entries.whatsapp = {};
            cfg.plugins.entries.whatsapp.enabled = true;
            if (!cfg.plugins.allow) cfg.plugins.allow = [];
            if (!cfg.plugins.allow.includes('matrix')) cfg.plugins.allow.push('matrix');
            if (!cfg.plugins.allow.includes('whatsapp')) cfg.plugins.allow.push('whatsapp');
            fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
            console.log('Config updated: plugins enabled, env vars substituted');
          "
          echo "Starting gateway..."
          exec node dist/index.js gateway run --allow-unconfigured
        ''
      ];
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
        size = "10Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [{ path = "/home/node"; }];
      };
      config = {
        filename = "openclaw.json";
        mountPath = "/config";
        data = {
          agents = {
            list = [
              {
                id = "main";
                identity = {
                  name = "Mel";
                  theme = "minha fiel assistente";
                  emoji = "🐕"; # dog emoji
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
            allow = [ "matrix" ];
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
      values = {
        ingress.main.enabled = false;
        controllers.main.containers.main.securityContext = {
          runAsUser = 0;
          runAsGroup = 0;
        };
        controllers.main.serviceAccount.name = "openclaw";
        defaultPodOptions.automountServiceAccountToken = true;
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
        controllers.main.containers.main.env.XDG_CONFIG_HOME = "/home/node/.config";
        controllers.main.containers.main.env.HOME = "/home/node";
        controllers.main.containers.main.env.TZ = "America/Sao_Paulo";
        controllers.main.containers.main.env.PATH =
          "/home/node/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
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
            TS_HOSTNAME = "openclaw";
            TS_USERSPACE = "false";
            TS_STATE_DIR = "/var/lib/tailscale";
            TS_ACCEPT_DNS = "false";
            TS_AUTH_ONCE = "true";
            TS_KUBE_SECRET = "";
          };
        };
        persistence.tailscale-state = {
          type = "persistentVolumeClaim";
          storageClass = "rook-ceph-block";
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          advancedMounts.main.tailscale = [{ path = "/var/lib/tailscale"; }];
        };
        persistence.shared-storage = {
          type = "persistentVolumeClaim";
          existingClaim = "cephfs-shared-storage-root";
          advancedMounts.main.main = [{ path = "/home/node/shared"; }];
        };
        persistence.dev-tun = {
          type = "hostPath";
          hostPath = "/dev/net/tun";
          advancedMounts.main.tailscale = [{ path = "/dev/net/tun"; }];
        };
        controllers.main.initContainers.copy-config = {
          image = {
            repository = "busybox";
            tag = "latest";
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
          command = [
            "sh"
            "-c"
            "mkdir -p /home/node/.openclaw && cp /config/openclaw.json /home/node/.openclaw/openclaw.json && rm -rf /home/node/.openclaw/extensions /home/node/.config/openclaw/extensions"
          ];
        };
        controllers.main.initContainers.install-tools = {
          image = {
            repository = "node";
            tag = "22-slim";
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
          command = [
            "bash"
            "-c"
            ''
              set -e
              mkdir -p /home/node/.local/bin
              chown -R 1000:1000 /home/node/.local

              # Install curl, jq, git, python3-pip and other deps
              apt-get update && apt-get install -y curl xz-utils jq git python3-pip

              # Install requests library for Python in user directory
              if [ ! -d /home/node/.local/lib/python3.*/site-packages/requests ]; then
                echo "Installing requests library..."
                pip3 install --user --no-cache-dir --break-system-packages requests
                echo "requests installed successfully"
              else
                echo "requests already exists, skipping..."
              fi

              # Install ffmpeg
              if [ ! -f /home/node/.local/bin/ffmpeg ]; then
                echo "Installing ffmpeg..."
                # Download from John Van Sickle (reliable static builds)
                curl -fsSL -o /tmp/ffmpeg.tar.xz "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
                tar -xf /tmp/ffmpeg.tar.xz -C /tmp/
                # Find the ffmpeg binary in the extracted folder (it's usually in a subdirectory)
                find /tmp -name "ffmpeg" -type f -executable | head -1 | xargs -I {} cp {} /home/node/.local/bin/ffmpeg
                chmod +x /home/node/.local/bin/ffmpeg
                rm -rf /tmp/ffmpeg.tar.xz /tmp/ffmpeg*
                echo "ffmpeg installed successfully"
              else
                echo "ffmpeg already exists, skipping..."
              fi

              # Install uv
              if [ ! -f /home/node/.local/bin/uv ]; then
                echo "Installing uv..."
                curl -fsSL https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/home/node/.local/bin sh
                echo "uv installed successfully"
              else
                echo "uv already exists, skipping..."
              fi

              # Install Gemini CLI
              if [ ! -f /home/node/.local/bin/gemini ]; then
                echo "Installing Gemini CLI..."
                # Install locally - npm creates lib/ inside prefix
                mkdir -p /home/node/.local/lib/node_modules
                npm install @google/gemini-cli --prefix /home/node/.local
                # Create symlink to the binary (npm puts it in prefix/lib/node_modules/.bin/)
                ln -sf /home/node/.local/lib/node_modules/.bin/gemini /home/node/.local/bin/gemini
                echo "Gemini CLI installed successfully"
              else
                echo "Gemini CLI already exists, skipping..."
              fi

              # Install GitHub CLI (gh)
              if [ ! -f /home/node/.local/bin/gh ]; then
                echo "Installing GitHub CLI..."
                # Download latest gh CLI release for Linux amd64
                curl -fsSL -o /tmp/gh.tar.gz "https://github.com/cli/cli/releases/latest/download/gh_$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name' | sed 's/v//')_linux_amd64.tar.gz"
                tar -xzf /tmp/gh.tar.gz -C /tmp/
                # Find and copy the gh binary
                find /tmp -name "gh" -type f -executable | head -1 | xargs -I {} cp {} /home/node/.local/bin/gh
                chmod +x /home/node/.local/bin/gh
                rm -rf /tmp/gh.tar.gz /tmp/gh_*
                echo "GitHub CLI installed successfully"
              else
                echo "GitHub CLI already exists, skipping..."
              fi

              # Set ownership
              chown -R 1000:1000 /home/node/.local
              ls -la /home/node/.local/bin/
              echo "All tools installed successfully!"
            ''
          ];
        };
      };
    };
  };
}

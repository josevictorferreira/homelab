{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.openclaw = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/openclaw/openclaw";
        tag = "2026.2.14@sha256:ace6f32961c4d574cb189d0007ec778408a9c02502f38af9ded6c864bae0f454";
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
            const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
            if (!cfg.plugins) cfg.plugins = {};
            if (!cfg.plugins.entries) cfg.plugins.entries = {};
            if (!cfg.plugins.entries.matrix) cfg.plugins.entries.matrix = {};
            cfg.plugins.entries.matrix.enabled = true;
            if (!cfg.plugins.allow) cfg.plugins.allow = [];
            if (!cfg.plugins.allow.includes('matrix')) cfg.plugins.allow.push('matrix');
            fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
            console.log('Config updated: matrix plugin enabled');
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
        globalMounts = [ { path = "/home/node"; } ];
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
                  name = "Clawd";
                  theme = "helpful AI assistant";
                  emoji = "🦞";
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
            media = {
              audio = {
                enabled = true;
                maxBytes = 20971520;
                models = [
                  {
                    type = "cli";
                    command = "gemini";
                    args = [
                      "--api-key"
                      "\${GEMINI_API_KEY}"
                      "-p"
                      "Transcribe this audio file: {{`{{`}}MediaPath{{`}}`}}"
                    ];
                    timeoutSeconds = 60;
                  }
                ];
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
            level = "info";
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
          };
          env = {
            MOONSHOT_API_KEY = "\${MOONSHOT_API_KEY}";
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
          advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
        };
        persistence.shared-storage = {
          type = "persistentVolumeClaim";
          existingClaim = "cephfs-shared-storage-root";
          advancedMounts.main.main = [ { path = "/home/node/shared"; } ];
        };
        persistence.dev-tun = {
          type = "hostPath";
          hostPath = "/dev/net/tun";
          advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
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
            ''
              mkdir -p /home/node/.local/bin

              # Install ffmpeg if not present
              if [ ! -f /home/node/.local/bin/ffmpeg ]; then
              echo "Installing ffmpeg..."
              curl -L -o /home/node/.local/bin/ffmpeg https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-linux-x64 \
                && chmod +x /home/node/.local/bin/ffmpeg
              echo "Installing uv..."
              curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/home/node/.local/bin sh
              echo "Installing Gemini CLI..."
              npm install -g @google/gemini-cli --prefix /home/node/.local
              echo "Tools installed successfully"
            ''
          ];
        };
      };
    };
  };
}

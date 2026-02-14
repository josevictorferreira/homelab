{ kubenix, homelab, ... }:

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
        tag = "latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5";
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
              "fetch"
            ];
            deny = [ "browser" ];
            media = {
              audio = {
                enabled = true;
                maxBytes = 20971520;
                models = [

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
              accessToken = kubenix.lib.secretsInlineFor "openclaw_matrix_token";
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
            MOONSHOT_API_KEY = kubenix.lib.secretsInlineFor "moonshot_api_key";
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
      };
    };
  };
}

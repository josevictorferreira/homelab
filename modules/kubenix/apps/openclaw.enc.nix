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
        "node"
        "dist/index.js"
        "gateway"
        "--allow-unconfigured"
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
          };
          gateway = {
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
                policy = "pairing";
                allowFrom = [ "@jose:josevictor.me" ];
              };
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
        # Main container runs as root so agent can install packages
        controllers.main.containers.main.securityContext = {
          runAsUser = 0;
          runAsGroup = 0;
        };
        # Tailscale sidecar for tailnet access (kernel mode)
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
            TS_ACCEPT_DNS = "true";
            TS_AUTH_ONCE = "true";
            TS_KUBE_SECRET = "";
          };
        };
        # Tailscale state persistence
        persistence.tailscale-state = {
          type = "persistentVolumeClaim";
          storageClass = "rook-ceph-block";
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
        };
        # tun device for kernel-mode tailscale
        persistence.dev-tun = {
          type = "hostPath";
          hostPath = "/dev/net/tun";
          advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
        };
        # Hide the bundled (dep-less) matrix plugin so only our persistent copy loads
        # Only mount on main container, NOT init containers
        persistence.hide-bundled-matrix = {
          type = "emptyDir";
          advancedMounts.main.main = [ { path = "/app/extensions/matrix"; } ];
        };
        controllers.main.initContainers = {
          copy-config = {
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
              "mkdir -p /home/node/.openclaw && cp /config/openclaw.json /home/node/.openclaw/openclaw.json"
            ];
          };
          install-matrix-plugin = {
            image = {
              repository = "ghcr.io/openclaw/openclaw";
              tag = "latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5";
              pullPolicy = "IfNotPresent";
            };
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
            };
            command = [
              "sh"
              "-c"
              ''
                set -e

                PLUGIN_DIR="/home/node/.openclaw/extensions/matrix"

                # Check if already installed with all deps (including native binary)
                if [ -d "$PLUGIN_DIR/node_modules/@vector-im/matrix-bot-sdk" ] && \
                   [ -d "$PLUGIN_DIR/node_modules/markdown-it" ] && \
                   [ -d "$PLUGIN_DIR/node_modules/@matrix-org/matrix-sdk-crypto-nodejs-linux-x64-gnu" ]; then
                  echo "Matrix plugin deps already installed"
                  exit 0
                fi

                echo "Setting up matrix plugin in persistent volume..."

                # Copy plugin source from bundled location (not hidden here - emptyDir only on main)
                rm -rf "$PLUGIN_DIR"
                mkdir -p "$PLUGIN_DIR"
                cp -r /app/extensions/matrix/* "$PLUGIN_DIR/"

                # Remove devDependencies (workspace ref) from package.json
                cd "$PLUGIN_DIR"
                sed -i '/"devDependencies"/,/}/d' package.json
                # Remove trailing comma before closing brace if any
                sed -i ':a;N;$!ba;s/,\n}/\n}/g' package.json

                # Allow native module build scripts (pnpm v10+ blocks them by default)
                # Without this, @matrix-org/matrix-sdk-crypto-nodejs postinstall won't run
                # and the platform-specific binary won't be downloaded
                node -e "
                  const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
                  pkg.pnpm = { onlyBuiltDependencies: ['@matrix-org/matrix-sdk-crypto-nodejs'] };
                  require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2));
                "

                echo "Installing dependencies with pnpm..."
                pnpm install --no-frozen-lockfile 2>&1

                echo "Matrix plugin installed successfully"
              ''
            ];
          };
        };
      };
    };
  };
}

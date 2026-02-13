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
          echo "Starting gateway..."
          cd /app
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
        # Tailscale kernel-mode overwrites resolv.conf with MagicDNS (100.100.100.100)
        # which can't resolve K8s service names. Use explicit dnsConfig with cluster DNS.
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
        # XDG_CONFIG_HOME on persistent volume so plugin installs survive restarts
        controllers.main.containers.main.env.XDG_CONFIG_HOME = "/home/node/.config";
        controllers.main.containers.main.env.HOME = "/home/node";
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
        # Copy config to persistent volume; matrix plugin installed at startup
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

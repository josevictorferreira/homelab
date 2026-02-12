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
        globalMounts = [ { path = "/home/node/.openclaw"; } ];
      };
      # Config mounted to /config, then copied by initContainer to PVC
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
                primary = "moonshot/kimi-k2.5";
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
          # Matrix channel configuration
          channels = {
            matrix = {
              enabled = true;
              homeserver = "http://synapse-matrix-synapse:8008";
              accessToken = kubenix.lib.secretsFor "openclaw_matrix_token";
              userId = "@openclaw:josevictor.me";
              encryption = false;
              dm = {
                policy = "pairing";
                allowFrom = [ "@jose:josevictor.me" ];
              };
              groupPolicy = "disabled";
            };
          };
          # Environment variables for API keys
          env = {
            MOONSHOT_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
          };
          # Model providers configuration
          models = {
            mode = "merge";
            providers = {
              moonshot = {
                baseUrl = "https://api.moonshot.ai/v1";
                apiKey = "\${MOONSHOT_API_KEY}";
                api = "openai-completions";
                models = [
                  {
                    id = "kimi-k2.5";
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
        # InitContainer copies config from ConfigMap to PVC
        controllers.main.initContainers.copy-config = {
          image = {
            repository = "busybox";
            tag = "latest";
          };
          command = [
            "sh"
            "-c"
            "cp /config/openclaw.json /home/node/.openclaw/openclaw.json && chown 1000:1000 /home/node/.openclaw/openclaw.json"
          ];
        };
        # InitContainer to install Matrix plugin
        controllers.main.initContainers.install-matrix-plugin = {
          image = {
            repository = "ghcr.io/openclaw/openclaw";
            tag = "latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5";
          };
          command = [
            "sh"
            "-c"
            ''
              if [ -d /home/node/.openclaw/extensions/matrix/node_modules/@vector-im ]; then
                echo "Matrix plugin already installed"
                exit 0
              fi
              echo "Installing Matrix plugin..."
              mkdir -p /home/node/.openclaw/extensions
              cp -r /app/extensions/matrix /home/node/.openclaw/extensions/
              cd /home/node/.openclaw/extensions/matrix
              # Remove devDependencies that use workspace:* protocol
              cat package.json | grep -v "devDependencies\|workspace" | sed 's/,\s*}/}/g' > package.json.tmp
              mv package.json.tmp package.json
              npm install
              chown -R 1000:1000 /home/node/.openclaw/extensions
              echo "Matrix plugin installed successfully"
            ''
          ];
        };
      };
    };
  };
}

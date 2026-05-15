{ kubenix, homelab, ... }:

let
  name = "openclaw";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 18789;
  host = "openclaw-debian.${homelab.domain}";
  image = "ghcr.io/josevictorferreira/openclaw-debian:2026.5.12-luna-hindsight-lossless@sha256:b35af506302760641156c23bdfe99c1875968077f4359eecd87da5a1f00ca512";
  startupScript = ''
            set -euo pipefail

            SHARED_DIR=/home/node/.openclaw
            SHARED_CONFIG="$SHARED_DIR/openclaw.json"
            LOCAL_DIR=/home/node/.local
            STATE_DIR="$LOCAL_DIR/openclaw"
            CONFIG_FILE="$STATE_DIR/openclaw.json"
            EXTENSIONS_DIR="$STATE_DIR/extensions"
            PLUGIN_STAGE_DIR="$STATE_DIR/plugin-stage"

            echo "Preparing OpenClaw Debian Luna node..."
            for i in $(seq 1 30); do
              if [ -f "$SHARED_CONFIG" ] && touch "$SHARED_DIR/.debian-node-mount-check" 2>/dev/null; then
                rm -f "$SHARED_DIR/.debian-node-mount-check"
                break
              fi
              echo "Waiting for shared OpenClaw config, attempt $i/30..."
              sleep 2
            done

            if [ ! -f "$SHARED_CONFIG" ]; then
              echo "Shared OpenClaw config not found at $SHARED_CONFIG" >&2
              exit 1
            fi

            mkdir -p "$LOCAL_DIR/bin" "$LOCAL_DIR/lib/node_modules" "$STATE_DIR" "$EXTENSIONS_DIR" "$PLUGIN_STAGE_DIR"
            mkdir -p "$STATE_DIR/logs" "$STATE_DIR/tmp" "$STATE_DIR/workspace-luna"

            echo "Syncing tested plugin bundle into persisted local state..."
            if [ ! -f "$EXTENSIONS_DIR/.synced" ]; then
              cp -a /opt/openclaw-debian/extensions/. "$EXTENSIONS_DIR/"
              touch "$EXTENSIONS_DIR/.synced"
              echo "Plugin sync complete."
            else
              echo "Plugins already synced, skipping copy."
            fi

            echo "Generating Luna-only runtime config at $CONFIG_FILE..."
            node -e '
    const fs = require("fs");

    const sourcePath = process.env.SHARED_CONFIG;
    const targetPath = process.env.OPENCLAW_CONFIG_PATH;
    const config = JSON.parse(fs.readFileSync(sourcePath, "utf8"));

    config.agents ??= {};
    config.agents.list = [
      {
        id: "luna",
        workspace: "/home/node/.openclaw/workspace-luna",
        model: {
          primary: "zai-coding-plan/glm-5.1",
          fallbacks: ["opencode-go/glm-5.1", "huggingface/zai-org/glm-5.1"],
        },
        identity: { name: "Luna", theme: "minha fiel companheira", emoji: "🐕", avatar: "avatars/luna.png" },
        reasoningDefault: "off",
      },
    ];
    config.bindings = [
      { agentId: "luna", match: { channel: "matrix", accountId: "luna" } },
    ];

    config.plugins ??= {};
    config.plugins.enabled = true;
    config.plugins.slots ??= {};
    config.plugins.slots.memory = "hindsight-openclaw";
    config.plugins.slots.contextEngine = "legacy";
    config.plugins.entries ??= {};
    delete config.plugins.entries["memory-lancedb"];
    config.plugins.entries["hindsight-openclaw"] = {
      ...(config.plugins.entries["hindsight-openclaw"] ?? {}),
      enabled: true,
      hooks: {
        ...(config.plugins.entries["hindsight-openclaw"]?.hooks ?? {}),
        allowConversationAccess: true,
      },
    };
    delete config.plugins.entries["lossless-claw"];
    config.plugins.entries.matrix = {
      ...(config.plugins.entries.matrix ?? {}),
      enabled: true,
    };
    config.plugins.entries.whatsapp = {
      ...(config.plugins.entries.whatsapp ?? {}),
      enabled: false,
    };

    // Construct Luna Matrix account from env var (avoids depending on shared config)
    config.channels ??= {};
    config.channels.matrix ??= {};
    config.channels.matrix.enabled = true;
    config.channels.matrix.accounts = {
      luna: {
        userId: "@luna:josevictor.me",
        homeserver: "http://tuwunel.apps.svc.cluster.local:8008",
        accessToken: process.env.LUNA_MATRIX_TOKEN || "",
        name: "Luna",
        network: { dangerouslyAllowPrivateNetwork: true },
      },
    };
    if (config.channels?.whatsapp) {
      config.channels.whatsapp.enabled = false;
    }

    fs.writeFileSync(targetPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
    '

            cd "$STATE_DIR/workspace-luna"
            exec node /app/openclaw.mjs gateway --port ${toString port} --bind lan --allow-unconfigured --verbose
  '';
in
{
  kubernetes.resources = {
    persistentVolumeClaims.openclaw-local = {
      metadata = { inherit namespace; };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = kubenix.lib.defaultStorageClass;
        resources.requests.storage = "10Gi";
      };
    };

    deployments.${name} = {
      metadata = {
        inherit name namespace;
        labels.app = name;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            automountServiceAccountToken = false;
            imagePullSecrets = [
              { name = "ghcr-registry-secret"; }
            ];
            terminationGracePeriodSeconds = 60;
            affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = [ "lab-delta-cp" ];
                  }
                ];
              }
            ];
            containers = [
              {
                inherit name image;
                imagePullPolicy = "Always";
                command = [
                  "/bin/bash"
                  "-lc"
                  startupScript
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = port;
                    protocol = "TCP";
                  }
                ];
                envFrom = [
                  { secretRef.name = "openclaw-config"; }
                ];
                env = [
                  {
                    name = "HOME";
                    value = "/home/node";
                  }
                  {
                    name = "OPENCLAW_CONFIG_PATH";
                    value = "/home/node/.local/openclaw/openclaw.json";
                  }
                  {
                    name = "OPENCLAW_DATA_DIR";
                    value = "/home/node/.local/openclaw";
                  }
                  {
                    name = "OPENCLAW_STATE_DIR";
                    value = "/home/node/.local/openclaw";
                  }
                  {
                    name = "SHARED_CONFIG";
                    value = "/home/node/.openclaw/openclaw.json";
                  }
                  {
                    name = "OPENCLAW_PLUGIN_STAGE_DIR";
                    value = "/home/node/.local/openclaw/plugin-stage";
                  }
                  {
                    name = "OPENCLAW_DISABLE_BONJOUR";
                    value = "1";
                  }
                  {
                    name = "OPENCLAW_NO_RESPAWN";
                    value = "1";
                  }
                  {
                    name = "OPENCLAW_ALLOW_ROOT";
                    value = "1";
                  }
                  {
                    name = "NPM_CONFIG_PREFIX";
                    value = "/home/node/.local";
                  }
                  {
                    name = "NODE_PATH";
                    value = "/home/node/.local/lib/node_modules:/app/node_modules";
                  }
                  {
                    name = "PATH";
                    value = "/home/node/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
                  }
                  {
                    name = "NODE_OPTIONS";
                    value = "--unhandled-rejections=warn";
                  }
                  {
                    name = "TZ";
                    value = homelab.timeZone;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "250m";
                    memory = "2Gi";
                  };
                };
                securityContext = {
                  runAsUser = 0;
                  runAsGroup = 0;
                };
                startupProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  failureThreshold = 60;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 300;
                  periodSeconds = 60;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                volumeMounts = [
                  {
                    name = "openclaw-shared";
                    mountPath = "/home/node/.openclaw";
                    subPath = "openclaw";
                  }
                  {
                    name = "openclaw-local";
                    mountPath = "/home/node/.local";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "openclaw-shared";
                persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
              }
              {
                name = "openclaw-local";
                persistentVolumeClaim.claimName = "openclaw-local";
              }
            ];
          };
        };
      };
    };

    services.${name} = {
      metadata = {
        inherit name namespace;
      };
      spec = {
        type = "ClusterIP";
        selector.app = name;
        ports = [
          {
            name = "http";
            inherit port;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
      };
    };

    ingresses.${name} = {
      metadata = {
        inherit name namespace;
        annotations."cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
      };
      spec = {
        ingressClassName = kubenix.lib.defaultIngressClass;
        rules = [
          {
            inherit host;
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  inherit name;
                  port.number = port;
                };
              }
            ];
          }
        ];
        tls = [
          {
            hosts = [ host ];
            secretName = kubenix.lib.defaultTLSSecret;
          }
        ];
      };
    };
  };
}

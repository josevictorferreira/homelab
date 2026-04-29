{ kubenix, homelab, ... }:

let
  name = "openclaw";
  namespace = homelab.kubernetes.namespaces.applications;
  configName = "openclaw-test-config";
  port = 18789;
  host = "openclaw-test.${homelab.domain}";
  image = "ghcr.io/openclaw/openclaw:2026.4.26@sha256:2e32f4f2e4f653f12d5dc6e5c93cc71e60f49d1dfaf061b18e53c3e61a38fb48";
  losslessClawVersion = "0.9.2";
  startupScript = ''
            set -euo pipefail

            STATE_DIR=/persistent/openclaw
            HOME_DIR=$STATE_DIR/home
            mkdir -p "$STATE_DIR" "$HOME_DIR"

            if [ ! -f "$STATE_DIR/.openclaw-ready" ]; then
              echo "Initializing persistent OpenClaw state..."
              mkdir -p "$HOME_DIR/.openclaw" "$HOME_DIR/.cache" "$HOME_DIR/.local" "$HOME_DIR/workspace"
              touch "$STATE_DIR/.openclaw-ready"
              echo "Persistent state initialized."
            else
              echo "Using existing persistent state at $STATE_DIR"
            fi

            mkdir -p "$HOME_DIR/.openclaw" "$HOME_DIR/.cache/ms-playwright" "$HOME_DIR/workspace"

            if [ ! -f "$HOME_DIR/.openclaw/openclaw.json" ]; then
              echo "Seeding OpenClaw config from ConfigMap..."
              cp /config/config-template.json "$HOME_DIR/.openclaw/openclaw.json"
            fi

            export HOME=/root
            export OPENCLAW_DATA_DIR=/root/.openclaw
            export OPENCLAW_STATE_DIR=/root/.openclaw
            export OPENCLAW_CONFIG_PATH=/root/.openclaw/openclaw.json
            export OPENCLAW_PLUGIN_STAGE_DIR=/tmp/openclaw-plugin-stage
            export NPM_CONFIG_PREFIX=/usr/local
            export PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

            mount --bind "$HOME_DIR" /root

            sync_plugin_config() {
              echo "Ensuring required OpenClaw plugins are enabled..."
              node <<'NODE'
    const fs = require("fs");

    const configPath = "/root/.openclaw/openclaw.json";
    const requiredPlugins = ["lossless-claw", "matrix"];

    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    config.plugins ??= {};
    config.plugins.enabled = true;

    const allow = new Set(Array.isArray(config.plugins.allow) ? config.plugins.allow : []);
    for (const plugin of requiredPlugins) allow.add(plugin);
    config.plugins.allow = Array.from(allow);

    config.plugins.entries ??= {};
    config.plugins.entries.matrix = {
      ...(config.plugins.entries.matrix ?? {}),
      enabled: true,
    };

    config.plugins.entries["lossless-claw"] = {
      ...(config.plugins.entries["lossless-claw"] ?? {}),
      enabled: true,
      config: {
        ...((config.plugins.entries["lossless-claw"] ?? {}).config ?? {}),
        enabled: true,
      },
    };

    fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
    NODE
            }

            install_lossless_claw() {
              plugin_dir=/root/.openclaw/extensions/lossless-claw
              if [ -f "$plugin_dir/openclaw.plugin.json" ]; then
                echo "lossless-claw plugin already installed."
                return
              fi

              echo "Installing lossless-claw plugin into persistent OpenClaw state..."
              tmp_dir="$(mktemp -d)"
              trap 'rm -rf "$tmp_dir"' EXIT
              rm -rf "$plugin_dir"
              mkdir -p "$plugin_dir"
              npm pack @martian-engineering/lossless-claw@${losslessClawVersion} --pack-destination "$tmp_dir" >/dev/null
              tar -xzf "$tmp_dir"/martian-engineering-lossless-claw-${losslessClawVersion}.tgz -C "$plugin_dir" --strip-components=1
              npm install --omit=dev --ignore-scripts --legacy-peer-deps --prefix "$plugin_dir"
              echo "lossless-claw plugin installed."
            }

            sync_plugin_config
            install_lossless_claw

            cd /root/workspace
            exec node /app/openclaw.mjs gateway --port 18789 --bind lan --allow-unconfigured --verbose
  '';
in
{
  kubernetes.resources = {
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
            terminationGracePeriodSeconds = 60;
            affinity.nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "NotIn";
                      values = [
                        "lab-delta-cp"
                        "lab-alpha-cp"
                      ];
                    }
                  ];
                }
              ];
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = [ "lab-beta-cp" ];
                    }
                  ];
                }
              ];
            };
            containers = [
              {
                inherit name image;
                imagePullPolicy = "IfNotPresent";
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
                  { secretRef.name = configName; }
                ];
                env = [
                  {
                    name = "HOME";
                    value = "/root";
                  }
                  {
                    name = "OPENCLAW_DATA_DIR";
                    value = "/root/.openclaw";
                  }
                  {
                    name = "OPENCLAW_STATE_DIR";
                    value = "/root/.openclaw";
                  }
                  {
                    name = "OPENCLAW_CONFIG_PATH";
                    value = "/root/.openclaw/openclaw.json";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "2Gi";
                  };
                };
                securityContext = {
                  runAsUser = 0;
                  runAsGroup = 0;
                  allowPrivilegeEscalation = true;
                  capabilities.add = [
                    "SYS_ADMIN"
                    "SYS_CHROOT"
                  ];
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
                    name = "persistent";
                    mountPath = "/persistent";
                  }
                  {
                    name = "config";
                    mountPath = "/config";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "persistent";
                persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
              }
              {
                name = "config";
                configMap.name = configName;
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

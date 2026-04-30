{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  appImage = {
    repository = "ghcr.io/josevictorferreira/openclaw-nix";
    tag = "v2026.4.29-beta.1-matrix-touch-noop-webm-audio@sha256:3e59b4ea4a5e7cf3e27b5ba4e69e180874003cce4519cc44e3d8f1f187bf8d3a";
    pullPolicy = "Always";
  };
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
      image = appImage;
      port = 18789;
      replicas = 1;
      secretName = "openclaw-config";

      # Resource limits - increased to handle Matrix E2EE initialization
      resources = {
        requests = {
          cpu = "250m";
          memory = "512Mi";
        };
        limits = {
          cpu = "1500m";
          memory = "2Gi";
        };
      };
      priorityClassName = "high-priority";

      # Main persistence: use default (disabled) — custom volumes via values
      values = {
        # Enable ingress for external access
        ingress.main = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          annotations = {
            "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
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
              secretName = kubenix.lib.defaultTLSSecret;
            }
          ];
        };
        # Override service type to ClusterIP (release default is LoadBalancer)
        service.main.type = "ClusterIP";

        defaultPodOptions.automountServiceAccountToken = true;
        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];
        defaultPodOptions.affinity.nodeAffinity = {
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

        # Security context: run as root for full access
        controllers.main = {
          strategy = "Recreate";
          containers = {
            main = {
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
              };

              env = {
                OPENCLAW_CONFIG_PATH = "/home/node/.openclaw/openclaw.json";
                OPENCLAW_DATA_DIR = "/home/node/.openclaw";
                OPENCLAW_STATE_DIR = "/home/node/.openclaw";
                HOME = "/home/node";
                TZ = homelab.timeZone;
                OPENCLAW_NIX_MODE = "1";
                NPM_CONFIG_PREFIX = "/home/node/.npm-global";
                OPENCLAW_PLUGIN_STAGE_DIR = "/tmp/openclaw-plugin-stage";
                PIP_TARGET = "/home/node/.local/lib/python";
                PYTHONPATH = "/home/node/.local/lib/python";
                PATH = "/home/node/.local/bin:/home/node/.npm-global/bin:/bin:/usr/bin";
                NODE_PATH = "/lib/openclaw/extensions/matrix/node_modules:/lib/openclaw/node_modules";
                MATRIX_MEL_ACCESS_TOKEN = {
                  valueFrom.secretKeyRef = {
                    name = "openclaw-config";
                    key = "MEL_MATRIX_TOKEN";
                  };
                };
                MATRIX_KIRA_ACCESS_TOKEN = {
                  valueFrom.secretKeyRef = {
                    name = "openclaw-config";
                    key = "KIRA_MATRIX_TOKEN";
                  };
                };
                MATRIX_LUNA_ACCESS_TOKEN = {
                  valueFrom.secretKeyRef = {
                    name = "openclaw-config";
                    key = "LUNA_MATRIX_TOKEN";
                  };
                };
                MATRIX_SPIKE_ACCESS_TOKEN = {
                  valueFrom.secretKeyRef = {
                    name = "openclaw-config";
                    key = "SPIKE_MATRIX_TOKEN";
                  };
                };
              };

              # Command: install matrix deps then start gateway
              command = [
                "bash"
                "-c"
                ''
                  set -e

                  # Wait for CephFS mount to be writable (avoids EACCES race on startup)
                  echo "Waiting for CephFS mount at /home/node/.openclaw..."
                  for i in $(seq 1 30); do
                    if touch /home/node/.openclaw/.mount-check 2>/dev/null; then
                      rm -f /home/node/.openclaw/.mount-check
                      echo "CephFS mount ready"
                      break
                    fi
                    echo "Mount not ready, attempt $i/30..."
                    sleep 2
                  done

                  # Ensure persistent directories exist for npm/pip packages
                  mkdir -p /home/node/.npm-global/bin
                  mkdir -p /home/node/.local/lib/python
                  mkdir -p /home/node/.local/bin
                  mkdir -p /home/node/.config
                  mkdir -p /home/node/.openclaw
                  mkdir -p "$OPENCLAW_PLUGIN_STAGE_DIR"

                  # Seed config from ConfigMap template if CephFS file doesn't exist yet
                  CONFIG_FILE="/home/node/.openclaw/openclaw.json"
                  if [ ! -f "$CONFIG_FILE" ]; then
                    echo "First run: seeding config from template..."
                    cp /etc/openclaw/config-template.json "$CONFIG_FILE"
                    echo "Config seeded at $CONFIG_FILE"
                  else
                    echo "Using existing config at $CONFIG_FILE"
                  fi

                  # Perform environment variable substitution on openclaw.json
                  # This ensures that tokens from secrets are correctly injected
                  echo "Performing environment variable substitution in $CONFIG_FILE..."
                  ALLOWLIST="OPENCLAW_MATRIX_TOKEN ELEVENLABS_API_KEY HUGGINGFACE_HUB_TOKEN KIMI_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY MINIMAX_API_KEY Z_AI_API_KEY ALIBABA_CODING_PLAN_API_KEY WHATSAPP_NUMBER WHATSAPP_BOT_NUMBER GEMINI_API_KEY GITHUB_TOKEN TS_AUTHKEY KIRA_MATRIX_TOKEN LUNA_MATRIX_TOKEN MEL_MATRIX_TOKEN SPIKE_MATRIX_TOKEN COPILOT_GITHUB_TOKEN"
                  for var_name in $ALLOWLIST; do
                    var_value=$(eval printf '%s' "\$$var_name")
                    if [ -n "$var_value" ]; then
                      escaped_value=$(echo "$var_value" | sed 's/[\\/&]/\\&/g')
                      sed -i "s|\\\''${$var_name}|$escaped_value|g" "$CONFIG_FILE"
                    fi
                  done
                  echo "Applying dynamic CephFS config patches..."
                  jq '.plugins = (.plugins // {}) | .plugins.enabled = true | .plugins.allow = (((.plugins.allow // []) + ["lossless-claw"]) | unique) | .plugins.slots = ((.plugins.slots // {}) | .memory = (.memory // "memory-core") | .contextEngine = "lossless-claw") | .plugins.entries = ((.plugins.entries // {}) | .["lossless-claw"] = ((.["lossless-claw"] // {}) | .enabled = true | .config = ((.config // {}) | .dbPath = "/home/node/.openclaw/lcm.db")))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                  echo "CephFS config patched"

                  echo "Materializing bundled OpenClaw plugin runtime dependencies from the Nix image..."
                  node --input-type=module <<'NODE'
                  import fs from "node:fs";
                  import path from "node:path";
                  import { pathToFileURL } from "node:url";

                  const packageRoot = "/lib/openclaw";
                  const bakedNodeModules = path.join(packageRoot, "node_modules");
                  const distDir = "/lib/openclaw/dist";
                  const runtimeDepsFile = fs.readdirSync(distDir).find((name) =>
                    name.startsWith("bundled-runtime-deps-") && name.endsWith(".js")
                  );
                  if (!runtimeDepsFile) {
                    throw new Error("bundled-runtime-deps module not found in " + distDir);
                  }

                  const runtimeDeps = await import(
                    pathToFileURL(path.join(distDir, runtimeDepsFile)).href
                  );
                  const scanBundledPluginRuntimeDeps = runtimeDeps.a;
                  const resolveBundledRuntimeDependencyPackageInstallRootPlan = runtimeDeps.l;
                  const createBundledRuntimeDepsInstallSpecs = runtimeDeps.n;

                  if (
                    typeof scanBundledPluginRuntimeDeps !== "function" ||
                    typeof resolveBundledRuntimeDependencyPackageInstallRootPlan !== "function" ||
                    typeof createBundledRuntimeDepsInstallSpecs !== "function"
                  ) {
                    throw new Error("bundled-runtime-deps exports are not in the expected shape");
                  }

                  const configPath = process.env.OPENCLAW_CONFIG_PATH;
                  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
                  const stageEnv = Object.fromEntries(
                    [
                      "HOME",
                      "NODE_PATH",
                      "NPM_CONFIG_PREFIX",
                      "OPENCLAW_CONFIG_PATH",
                      "OPENCLAW_DATA_DIR",
                      "OPENCLAW_NIX_MODE",
                      "OPENCLAW_PLUGIN_STAGE_DIR",
                      "OPENCLAW_STATE_DIR",
                      "PATH",
                    ]
                      .filter((name) => process.env[name] !== undefined)
                      .map((name) => [name, process.env[name]])
                  );
                  const scan = scanBundledPluginRuntimeDeps({
                    packageRoot,
                    config,
                    includeConfiguredChannels: false,
                    env: stageEnv,
                  });
                  if (scan.conflicts.length > 0) {
                    throw new Error(
                      "Conflicting bundled runtime dependency versions: " +
                        scan.conflicts.map((conflict) => conflict.name).join(", ")
                    );
                  }

                  const installSpecs = createBundledRuntimeDepsInstallSpecs({ deps: scan.deps });
                  const installRoot = resolveBundledRuntimeDependencyPackageInstallRootPlan(
                    packageRoot,
                    { env: stageEnv }
                  ).installRoot;
                  const dependencies = Object.fromEntries(
                    installSpecs
                      .map((spec) => {
                        const separator = spec.lastIndexOf("@");
                        return [spec.slice(0, separator), spec.slice(separator + 1)];
                      })
                      .sort(([left], [right]) => left.localeCompare(right))
                  );

                  fs.mkdirSync(installRoot, { recursive: true });
                  fs.rmSync(path.join(installRoot, ".openclaw-runtime-deps.lock"), {
                    recursive: true,
                    force: true,
                  });
                  fs.writeFileSync(
                    path.join(installRoot, "package.json"),
                    JSON.stringify({ name: "openclaw-runtime-deps-install", private: true, dependencies }, null, 2) + "\n",
                    "utf8"
                  );

                  const stagedNodeModules = path.join(installRoot, "node_modules");
                  const current = fs.existsSync(stagedNodeModules) ? fs.lstatSync(stagedNodeModules) : null;
                  if (current?.isSymbolicLink()) {
                    const target = fs.readlinkSync(stagedNodeModules);
                    if (path.resolve(installRoot, target) !== bakedNodeModules) {
                      fs.rmSync(stagedNodeModules, { recursive: true, force: true });
                    }
                  } else if (current) {
                    fs.rmSync(stagedNodeModules, { recursive: true, force: true });
                  }
                  if (!fs.existsSync(stagedNodeModules)) {
                    fs.symlinkSync(bakedNodeModules, stagedNodeModules, "dir");
                  }

                  for (const spec of installSpecs) {
                    const separator = spec.lastIndexOf("@");
                    const depName = spec.slice(0, separator);
                    if (!fs.existsSync(path.join(stagedNodeModules, depName, "package.json"))) {
                      throw new Error("Baked bundled runtime dependency is missing: " + spec);
                    }
                  }

                  console.log(
                    "Bundled runtime dependency stage materialized at " +
                      installRoot +
                      " (" +
                      installSpecs.length +
                      " specs)."
                  );
                  NODE
                  echo "Bundled OpenClaw plugin runtime dependencies prepared from baked image dependencies."

                  echo "Installing matrix plugin dependencies..."

                  # Find the actual nix store path where the gateway loads extensions from
                  MATRIX_EXT=$(readlink -f /lib/openclaw/extensions/matrix 2>/dev/null || echo "/lib/openclaw/extensions/matrix")

                  if [ -d "$MATRIX_EXT" ]; then
                    echo "Found matrix extension at: $MATRIX_EXT"
                    cd "$MATRIX_EXT"

                    if [ ! -d "node_modules/matrix-js-sdk" ]; then
                      echo "Installing npm dependencies..."
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

                  echo "Installing whatsapp plugin dependencies..."
                  WA_EXT=$(readlink -f /lib/openclaw/extensions/whatsapp 2>/dev/null || echo "/lib/openclaw/extensions/whatsapp")

                  if [ -d "$WA_EXT" ]; then
                    echo "Found whatsapp extension at: $WA_EXT"
                    cd "$WA_EXT"

                    if [ ! -d "node_modules/@whiskeysockets" ]; then
                      echo "Installing npm dependencies..."
                      node -e "
                        const fs = require('fs');
                        const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
                        delete pkg.devDependencies;
                        delete pkg.peerDependencies;
                        fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
                      "
                      npm install --omit=dev --no-package-lock --legacy-peer-deps 2>&1 || echo "WARN: npm install failed"
                      echo "WhatsApp plugin dependencies installed"
                    else
                      echo "node_modules already exists with deps, skipping"
                    fi
                  else
                    echo "WhatsApp extension not found at $WA_EXT"
                  fi

                  # Plugin sources already synced at image build time by oci-images/openclaw-nix/default.nix
                  exec node /lib/openclaw/dist/index.js gateway --port 18789
                ''
              ];
              probes = {
                readiness = {
                  enabled = true;
                  custom = true;
                  spec = {
                    tcpSocket = {
                      port = 18789;
                    };
                    initialDelaySeconds = 120;
                    periodSeconds = 15;
                    timeoutSeconds = 5;
                    failureThreshold = 30;
                  };
                };
              };
            };

            chromium = {
              image = appImage;
              securityContext = {
                runAsUser = 1000;
                runAsGroup = 1000;
                runAsNonRoot = true;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };

              env = {
                HOME = "/home/node/.chromium";
                TMPDIR = "/tmp";
              };

              command = [
                "/bin/chromium"
                "--headless=new"
                "--no-sandbox"
                "--disable-gpu"
                "--remote-debugging-address=0.0.0.0"
                "--remote-debugging-port=9222"
                "--user-data-dir=/home/node/.chromium/profile"
                "--disk-cache-dir=/home/node/.chromium/cache"
                "about:blank"
              ];

              resources = {
                requests = {
                  cpu = "250m";
                  memory = "512Mi";
                };
                limits = {
                  cpu = "1000m";
                  memory = "1Gi";
                };
              };

              probes = {
                startup = {
                  enabled = true;
                  custom = true;
                  spec = {
                    exec.command = [
                      "/bin/sh"
                      "-c"
                      "/bin/curl --fail --silent http://127.0.0.1:9222/json/version >/dev/null"
                    ];
                    failureThreshold = 30;
                    periodSeconds = 2;
                  };
                };
                readiness = {
                  enabled = true;
                  custom = true;
                  spec = {
                    exec.command = [
                      "/bin/sh"
                      "-c"
                      "/bin/curl --fail --silent http://127.0.0.1:9222/json/version >/dev/null"
                    ];
                    periodSeconds = 10;
                    timeoutSeconds = 2;
                  };
                };
                liveness = {
                  enabled = true;
                  custom = true;
                  spec = {
                    exec.command = [
                      "/bin/sh"
                      "-c"
                      "/bin/curl --fail --silent http://127.0.0.1:9222/json/version >/dev/null"
                    ];
                    periodSeconds = 10;
                    timeoutSeconds = 2;
                    failureThreshold = 3;
                  };
                };
              };
            };

            # Tailscale sidecar
            tailscale = {
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
          # ConfigMap: openclaw configuration template
          openclaw-config = {
            type = "configMap";
            name = "openclaw-config";
            advancedMounts.main.main = [
              {
                path = "/etc/openclaw";
                readOnly = true;
              }
            ];
          };

          # CephFS shared storage — single PVC, multiple subPath mounts
          # /home/node = openclaw-home subPath (HOME dir, persistent npm/pip, .config)
          # /home/node/.openclaw = openclaw subPath (workspace, memory, runtime state)
          # /home/node/shared = full CephFS root (cross-app access)
          shared-storage = {
            type = "persistentVolumeClaim";
            existingClaim = kubenix.lib.sharedStorage.rootPVC;
            advancedMounts.main.main = [
              {
                path = "/home/node";
                subPath = "openclaw-home";
              }
              {
                path = "/home/node/.openclaw";
                subPath = "openclaw";
              }
              { path = "/home/node/shared"; }
            ];
            advancedMounts.main.tailscale = [
              {
                path = "/var/lib/tailscale";
                subPath = "openclaw-tailscale-state";
              }
            ];
          };

          dev-tun = {
            type = "hostPath";
            hostPath = "/dev/net/tun";
            advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
          };

          chromium-data = {
            type = "emptyDir";
            advancedMounts.main.chromium = [
              { path = "/home/node/.chromium"; }
            ];
          };

          chromium-tmp = {
            type = "emptyDir";
            advancedMounts.main.chromium = [
              { path = "/tmp"; }
            ];
          };

          chromium-shm = {
            type = "emptyDir";
            medium = "Memory";
            sizeLimit = "1Gi";
            advancedMounts.main.chromium = [
              { path = "/dev/shm"; }
            ];
          };
        };
      };
    };
  };
}

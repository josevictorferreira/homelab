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
        tag = "v2026.3.28-beta.1@sha256:89f4b785c45f1b86da4a55c54b8a02798cc65958cfc983cbb11b0a478add0567";
        pullPolicy = "Always";
      };
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
              OPENCLAW_CONFIG_PATH = "/home/node/.openclaw/openclaw.json";
              OPENCLAW_DATA_DIR = "/home/node/.openclaw";
              OPENCLAW_STATE_DIR = "/home/node/.openclaw";
              HOME = "/home/node";
              TZ = "America/Sao_Paulo";
              NPM_CONFIG_PREFIX = "/home/node/.npm-global";
              PIP_TARGET = "/home/node/.local/lib/python";
              PYTHONPATH = "/home/node/.local/lib/python";
              PATH = "/home/node/.local/bin:/home/node/.npm-global/bin:/bin:/usr/bin";
              NODE_PATH = "/lib/openclaw/extensions/matrix/node_modules";
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

                # Seed config from ConfigMap template if CephFS file doesn't exist yet
                CONFIG_FILE="/home/node/.openclaw/openclaw.json"
                if [ ! -f "$CONFIG_FILE" ]; then
                  echo "First run: seeding config from template..."
                  cp /etc/openclaw/config-template.json "$CONFIG_FILE"

                  echo "Config seeded at $CONFIG_FILE"
                else
                  echo "Using existing config at $CONFIG_FILE"
                fi

                echo "Installing matrix plugin dependencies..."

                # Find the actual nix store path where the gateway loads extensions from
                MATRIX_EXT=$(readlink -f /lib/openclaw/extensions/matrix 2>/dev/null || echo "/lib/openclaw/extensions/matrix")

                if [ -d "$MATRIX_EXT" ]; then
                  echo "Found matrix extension at: $MATRIX_EXT"
                  cd "$MATRIX_EXT"

                  if [ ! -d "node_modules/@vector-im" ]; then
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

                # Copy plugin runtime TS sources into dist/extensions/ where the gateway resolver looks
                # The bundled build only includes compiled .js but jiti needs .ts source files
                echo "Syncing plugin sources to dist/extensions/..."
                for extdir in /lib/openclaw/extensions/*/; do
                  extname=$(basename "$extdir")
                  distdir="/lib/openclaw/dist/extensions/$extname"
                  if [ -d "$distdir" ]; then
                    for tsfile in "$extdir"*.ts; do
                      [ -f "$tsfile" ] && cp "$tsfile" "$distdir/" 2>/dev/null
                    done
                    [ -d "$extdir/src" ] && cp -r "$extdir/src" "$distdir/" 2>/dev/null
                    [ -f "$extdir/package.json" ] && cp "$extdir/package.json" "$distdir/" 2>/dev/null
                  fi
                done
                echo "Plugin sources synced"

                exec node /lib/openclaw/dist/index.js gateway --port 18789
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
            existingClaim = "cephfs-shared-storage-root";
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
          };

          # Tailscale sidecar persistence (block storage)
          tailscale-state = {
            type = "persistentVolumeClaim";
            storageClass = "rook-ceph-block";
            size = "1Gi";
            accessMode = "ReadWriteOnce";
            advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
          };

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

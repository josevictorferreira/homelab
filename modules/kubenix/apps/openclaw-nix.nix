{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  enableTailscaleSidecar = false;
  appImage = {
    repository = "ghcr.io/josevictorferreira/openclaw-nix";
    tag = "v2026.5.2-beta.2-matrix-touch-noop-webm-audio@sha256:b18eb1362e64c95ae81e7dd3a7fd7ce2a96d268eb2a6887b02b4bfee7a5680d7";
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

      resources = {
        requests = {
          cpu = "500m";
          memory = "512Mi";
        };
        limits = {
          cpu = "2000m";
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
                OPENCLAW_DATA_DIR = "/data/openclaw";
                OPENCLAW_STATE_DIR = "/data/openclaw";
                HOME = "/home/node";
                TZ = homelab.timeZone;
                OPENCLAW_NIX_MODE = "1";
                OPENCLAW_TRAJECTORY = "false";
                NPM_CONFIG_PREFIX = "/data/npm-global";
                OPENCLAW_PLUGIN_STAGE_DIR = "/data/plugin-stage";
                PIP_TARGET = "/data/local/lib/python";
                PYTHONPATH = "/data/local/lib/python";
                PATH = "/data/local/bin:/data/npm-global/bin:/bin:/usr/bin";
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


                  # Ensure persistent directories exist for npm/pip packages on /data block storage
                  mkdir -p /data/npm-global/bin
                  mkdir -p /data/local/lib/python
                  mkdir -p /data/local/bin
                  mkdir -p /data/plugin-stage
                  mkdir -p /data/openclaw
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
          }
          // (
            if enableTailscaleSidecar then
              {
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
              }
            else
              { }
          );

          # Service account for cluster-admin RBAC
          serviceAccount.name = "openclaw-nix";

          # DNS config: cluster DNS + Tailscale MagicDNS
          pod =
            if enableTailscaleSidecar then
              {
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
              }
            else
              { };
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

          # CephFS persistent config only. Runtime state/data live on RBD-backed /data.
          shared-storage = {
            type = "persistentVolumeClaim";
            existingClaim = kubenix.lib.sharedStorage.rootPVC;
            advancedMounts.main.main = [
              {
                path = "/home/node/.openclaw";
                subPath = "openclaw";
              }
              {
                path = "/shared/notetaking";
                subPath = "notetaking";
                readOnly = true;
              }
            ];
          };
        }
        // (
          if enableTailscaleSidecar then
            {
              dev-tun = {
                type = "hostPath";
                hostPath = "/dev/net/tun";
                advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
              };
              tailscale-state = {
                type = "persistentVolumeClaim";
                existingClaim = kubenix.lib.sharedStorage.rootPVC;
                advancedMounts.main.tailscale = [
                  {
                    path = "/var/lib/tailscale";
                    subPath = "openclaw-tailscale-state";
                  }
                ];
              };
            }
          else
            { }
        )
        // {

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
          data-block = {
            type = "persistentVolumeClaim";
            annotations."helm.sh/resource-policy" = "keep";
            accessMode = "ReadWriteOnce";
            size = "10Gi";
            storageClass = "rook-ceph-block";
            advancedMounts.main.main = [
              { path = "/data"; }
            ];
          };
          lcm-db = {
            type = "persistentVolumeClaim";
            annotations."helm.sh/resource-policy" = "keep";
            accessMode = "ReadWriteOnce";
            size = "5Gi";
            storageClass = "rook-ceph-block";
            advancedMounts.main.main = [
              { path = "/data/openclaw/lcm.db.d"; }
            ];
          };
        };
      };
    };
  };
}

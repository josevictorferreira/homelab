{ kubenix, homelab, ... }:

let
  name = "openclaw";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 18789;
  host = "openclaw-debian.${homelab.domain}";
  image = "ghcr.io/josevictorferreira/openclaw-debian:2026.5.27@sha256:ecfdcd987c0bf91e8ee90d16c4d802d624580798a493b48bbdcb542e375b218c";
  startupScript = ''
    set -euo pipefail

    SHARED_DIR=/home/node/.openclaw
    SHARED_CONFIG="$SHARED_DIR/openclaw.json"
    LOCAL_DIR=/home/node/.local
    STATE_DIR="$LOCAL_DIR/openclaw"
    EXTENSIONS_DIR="$STATE_DIR/extensions"
    PLUGIN_STAGE_DIR="$STATE_DIR/plugin-stage"

    echo "Preparing OpenClaw Debian node..."
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
    mkdir -p "$STATE_DIR/logs" "$STATE_DIR/tmp"

    echo "Syncing tested plugin bundle into persisted local state..."
    if [ ! -f "$EXTENSIONS_DIR/.synced" ]; then
      rm -rf "$EXTENSIONS_DIR"
      mkdir -p "$EXTENSIONS_DIR"
      cp -a /opt/openclaw-debian/extensions/. "$EXTENSIONS_DIR/"
      touch "$EXTENSIONS_DIR/.synced"
      echo "Plugin sync complete."
    else
      echo "Plugins already synced, skipping copy."
    fi

    # Set up in-cluster kubeconfig for kubectl
    mkdir -p "$HOME/.kube"
    cat > "$HOME/.kube/config" <<KUBECONFIG_EOF
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        server: https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT
      name: ze-homelab
    contexts:
    - context:
        cluster: ze-homelab
        namespace: ${namespace}
        user: openclaw
      name: default
    current-context: default
    users:
    - name: openclaw
      user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    KUBECONFIG_EOF

    echo "Using shared config directly from $SHARED_CONFIG"
    cd "$STATE_DIR"
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
        replicas = 0;
        strategy.type = "Recreate";
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;
            automountServiceAccountToken = true;
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
                    value = "/home/node/.openclaw/openclaw.json";
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
                    name = "OPENCLAW_PLUGIN_STAGE_DIR";
                    value = "/home/node/.local/openclaw/plugin-stage";
                  }
                  {
                    name = "OPENCLAW_DISABLE_BONJOUR";
                    value = "1";
                  }
                  # OPENCLAW_NO_RESPAWN removed — it prevented the health-monitor
                  # from restarting Matrix channels after startup-disable transient
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
                    name = "openclaw-shared";
                    mountPath = "/shared/notetaking";
                    subPath = "notetaking";
                  }
                  {
                    name = "openclaw-shared";
                    mountPath = "/shared/personal-finances";
                    subPath = "personal-finances";
                  }
                  {
                    name = "openclaw-shared";
                    mountPath = "/shared/mel-dynamica";
                    subPath = "mel-dynamica";
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

    serviceAccounts.${name} = {
      metadata = { inherit namespace; };
    };

    clusterRoleBindings.${name} = {
      metadata.labels.app = name;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "cluster-admin";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = name;
          inherit namespace;
        }
      ];
    };
  };
}

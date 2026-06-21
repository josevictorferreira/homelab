{ kubenix, homelab, ... }:

let
  name = "hermes-agent";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "docker.io/nousresearch/hermes-agent:v2026.6.19@sha256:9f367c7756ef087661a361536a89f438d57a122b958dc23d82d456b1433e6e9e";
  envFromSecret = [
    { secretRef.name = "${name}-env"; }
  ];
  dataVolumeMounts = [
    {
      name = "hermes-data";
      mountPath = "/opt/data";
      subPath = "hermes";
    }
    {
      name = "hermes-data";
      mountPath = "/shared/notetaking";
      subPath = "notetaking";
    }
    {
      name = "hermes-data";
      mountPath = "/shared/mel-dynamica";
      subPath = "mel-dynamica";
    }
    {
      name = "hermes-data";
      mountPath = "/shared/personal-finances";
      subPath = "personal-finances";
    }
    {
      name = "hermes-data";
      mountPath = "/shared/images";
      subPath = "images";
    }
    {
      name = "hermes-data";
      mountPath = "/opt/hermes/scripts/whatsapp-bridge/node_modules";
      subPath = "whatsapp-bridge-node_modules";
    }
  ];
  dataVolumes = [
    {
      name = "hermes-data";
      persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
    }
  ];
  commonSecurityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 10000;
    runAsGroup = 2002;
    capabilities.drop = [ "ALL" ];
  };
  # Profile dirs under /opt/data are setgid + group-owned by users (GID 100) and
  # private to "other" (o---). Both the gateway and the dashboard run as uid
  # 10000 (not the dir owner), so they must join GID 100 to traverse profile
  # dirs and read each profile's config.yaml.
  podSecurityContext = {
    supplementalGroups = [ 100 ];
  };
  cliWrapper = {
    name = "${name}-cli-wrapper";
    mountPath = "/usr/local/bin/hermes";
    volumeName = "cli-wrapper";
  };

  # Common env vars shared by the multiplex gateway + dashboard.
  commonEnv = [
    {
      name = "HERMES_UID";
      value = "10000";
    }
    {
      name = "HERMES_GID";
      value = "2002";
    }
    {
      name = "TZ";
      value = homelab.timeZone;
    }
    # OS home (shared): external CLI creds + the shared user-site under
    # /opt/data/.local. HERMES_HOME is set per-profile in the launcher below.
    {
      name = "HOME";
      value = "/opt/data";
    }
    # Managed scope: /opt/data/managed/config.yaml is overlaid (leaf-level,
    # managed wins) on top of every profile's config. Keys that must vary per
    # profile (model.default, skills.disabled, kanban.dispatch_in_gateway, and
    # WhatsApp enablement) are kept OUT of it; everything else is forced
    # identical across all profiles — the single shared config.
    {
      name = "HERMES_MANAGED_DIR";
      value = "/opt/data/managed";
    }
    # Drives the one-time WhatsApp bridge dependency bootstrap below. Per-profile
    # WhatsApp enablement comes from kira's own config/.env, not this var.
    {
      name = "WHATSAPP_BOOTSTRAP";
      value = "true";
    }
    # The image defaults HERMES_WRITE_SAFE_ROOT=/opt/data, which blocks agent
    # writes to the sibling /shared/* mounts ("protected system/credential file").
    # Empty disables the single-prefix restriction entirely (the code returns None
    # for an empty value); "/" does NOT work because it checks startswith("/"+"/")
    # == "//" and denies everything. The independent credential denylist
    # (ssh/.env/.aws/.kube/etc.) still protects secrets regardless.
    {
      name = "HERMES_WRITE_SAFE_ROOT";
      value = "";
    }
    {
      name = "AGENT_BROWSER_ENGINE";
      value = "cdp";
    }
    {
      name = "AGENT_BROWSER_ENDPOINT";
      value = "ws://cloakbrowser.${namespace}.svc.cluster.local:9222";
    }
    {
      name = "HINDSIGHT_MODE";
      value = "local_external";
    }
    {
      name = "HINDSIGHT_API_URL";
      value = "http://hindsight-api.${namespace}.svc.cluster.local:8888";
    }
    {
      name = "HINDSIGHT_BANK_ID";
      value = "hermes";
    }
    {
      name = "HINDSIGHT_BUDGET";
      value = "mid";
    }
    {
      name = "HINDSIGHT_API_KEY";
      value = "dummy";
    }
    {
      name = "HINDSIGHT_LLM_API_KEY";
      value = "dummy";
    }
    {
      name = "GITHUB_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "GITHUB_TOKEN";
      };
    }
    {
      name = "GH_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "GH_TOKEN";
      };
    }
    {
      name = "PATH";
      value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin";
    }
    {
      name = "PYTHONPATH";
      value = "/opt/data/.local/lib/python3.13/site-packages";
    }
    {
      name = "PYTHONUSERBASE";
      value = "/opt/data/.local";
    }
    {
      name = "PIP_USER";
      value = "true";
    }
    {
      name = "PIP_REQUIRE_VIRTUALENV";
      value = "false";
    }
  ];

  # Per-profile gateway containers.
  # Per-profile secrets injected as distinct env vars from the hermes-agent-env
  # secret. In multiplex mode every profile resolves its credentials from its
  # OWN profiles/<name>/.env, so the boot script materializes these into the
  # right .env before the multiplexer starts (a single process env var cannot
  # be per-profile).
  profileSecretEnv = [
    {
      name = "TED_MATRIX_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "MATRIX_ACCESS_TOKEN";
      };
    }
    {
      name = "KIRA_MATRIX_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "HERMES_KIRA_MATRIX_ACCESS_TOKEN";
      };
    }
    {
      name = "MEL_MATRIX_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "HERMES_MEL_MATRIX_ACCESS_TOKEN";
      };
    }
    {
      name = "SPIKE_MATRIX_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "HERMES_SPIKE_MATRIX_ACCESS_TOKEN";
      };
    }
    {
      name = "LUNA_MATRIX_TOKEN";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "HERMES_LUNA_MATRIX_ACCESS_TOKEN";
      };
    }
    {
      name = "KIRA_WHATSAPP_ALLOWED_USERS";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "HERMES_KIRA_WHATSAPP_ALLOWED_USERS";
      };
    }
  ];

  # Shared bootstrap. Runs ONCE in the single gateway container (previously once
  # per profile container). Installs into the shared user-site under /opt/data.
  bootstrap = ''
    # Group-writable by default so any hermes process (and the
    # host user, all in GID 100) can always overwrite shared files.
    umask 0002
    # Bootstrap pip if not present
    command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1 || {
      python3 -c "import urllib.request; exec(urllib.request.urlopen('https://bootstrap.pypa.io/get-pip.py').read())" --user -q 2>/dev/null || true
    }
    # Bootstrap faster-whisper for audio transcription
    python3 -c "import faster_whisper" 2>/dev/null || {
      pip install --user -q faster-whisper 2>/dev/null || true
    }
    # Bootstrap Matrix dependencies if not installed
    python3 -c "import mautrix" 2>/dev/null || {
      uv pip install mautrix asyncpg aiosqlite Markdown aiohttp-socks 2>/dev/null || true
    }
    # Bootstrap hindsight-client at the version the memory plugin pins.
    # The image bumps this pin on upgrade; the user-site copy on the PVC
    # persists the old version, so install the exact pin when it drifts.
    python3 -c "import importlib.metadata as m, sys; sys.exit(0 if m.version('hindsight-client') == '0.6.1' else 1)" 2>/dev/null || {
      python3 -m pip install --user --break-system-packages 'hindsight-client==0.6.1' 2>/dev/null || true
    }
    # Bootstrap kubectl if not present
    command -v kubectl >/dev/null 2>&1 || {
      python3 -c "
    import urllib.request, os, stat, shutil
    url = 'https://dl.k8s.io/release/v1.32.6/bin/linux/amd64/kubectl'
    tmp = '/tmp/kubectl'
    dest = '/opt/data/.local/bin/kubectl'
    os.makedirs('/opt/data/.local/bin', exist_ok=True)
    urllib.request.urlretrieve(url, tmp)
    os.chmod(tmp, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    shutil.move(tmp, dest)
            " 2>/dev/null || true
    }
    # Bootstrap WhatsApp bridge dependencies (kira is the only WhatsApp profile;
    # the bridge script is shared in the image so deps are installed once here).
    if [ "''${WHATSAPP_BOOTSTRAP:-false}" = "true" ]; then
      if [ -d /opt/hermes/scripts/whatsapp-bridge ] && [ ! -f /opt/hermes/scripts/whatsapp-bridge/node_modules/@whiskeysockets/baileys/package.json ]; then
        mkdir -p /opt/data/whatsapp-bridge-node_modules
        if [ ! -f /opt/data/whatsapp-bridge-node_modules/@whiskeysockets/baileys/package.json ]; then
          (cd /opt/hermes/scripts/whatsapp-bridge && cp -r node_modules /opt/data/whatsapp-bridge-node_modules 2>/dev/null) || true
          (cd /opt/hermes/scripts/whatsapp-bridge && NODE_OPTIONS="--max-old-space-size=256" npm install --production --no-audit --maxsockets 1 --prefer-offline 2>/dev/null) || true
          (cd /opt/hermes/scripts/whatsapp-bridge && cp -r node_modules /opt/data/whatsapp-bridge-node_modules 2>/dev/null) || true
        fi
        rm -rf /opt/hermes/scripts/whatsapp-bridge/node_modules
        ln -s /opt/data/whatsapp-bridge-node_modules /opt/hermes/scripts/whatsapp-bridge/node_modules
      fi
    fi
    # Fix Baileys 7.x syncFullHistory for incoming messages
    sed -i 's/syncFullHistory: false/syncFullHistory: true/' /opt/hermes/scripts/whatsapp-bridge/bridge.js 2>/dev/null || true
  '';

  # Launch every profile's gateway as a separate, self-restarting process inside
  # the SINGLE container. Each profile gets its OWN process env — most importantly
  # its own MATRIX_ACCESS_TOKEN — so per-profile Matrix accounts stay isolated.
  # (This Hermes version's gateway.multiplex_profiles cannot do per-profile Matrix
  # tokens: gateway config resolves MATRIX_ACCESS_TOKEN from the process-global
  # os.environ, so a single multiplexer process would force one token onto every
  # profile.) The shared config still comes from HERMES_MANAGED_DIR, so this is
  # one container with one shared config — only credentials differ per process.
  launchGateways = ''
    # run_gw <profile> <matrix-token> [EXTRA_ENV=val ...]
    # Self-restarting supervisor: if a profile's gateway exits, restart it after
    # a short backoff so one crash doesn't take down the others.
    run_gw() {
      prof="$1"; tok="$2"; shift 2
      while true; do
        env MATRIX_ACCESS_TOKEN="$tok" HERMES_HOME="/opt/data/profiles/$prof" "$@" \
          hermes -p "$prof" gateway run --no-supervise
        echo "[launcher] gateway $prof exited ($?); restarting in 5s" >&2
        sleep 5
      done
    }
    run_gw ted   "''${TED_MATRIX_TOKEN:-}"   &
    run_gw mel   "''${MEL_MATRIX_TOKEN:-}"   &
    run_gw spike "''${SPIKE_MATRIX_TOKEN:-}" &
    run_gw luna  "''${LUNA_MATRIX_TOKEN:-}"  &
    run_gw kira  "''${KIRA_MATRIX_TOKEN:-}" \
      WHATSAPP_ENABLED=true WHATSAPP_MODE=bot WHATSAPP_DEBUG=true \
      WHATSAPP_ALLOWED_USERS="''${KIRA_WHATSAPP_ALLOWED_USERS:-}" &
    wait
  '';

  # Single container running all five profile gateways.
  gatewayContainer = {
    name = "gateway";
    inherit image;
    imagePullPolicy = "IfNotPresent";
    command = [
      "/bin/sh"
      "-c"
      ''
        ${bootstrap}
        ${launchGateways}
      ''
    ];
    env = commonEnv ++ profileSecretEnv;
    envFrom = envFromSecret;
    volumeMounts = dataVolumeMounts ++ [
      {
        name = cliWrapper.volumeName;
        mountPath = cliWrapper.mountPath;
        subPath = "hermes";
      }
    ];
    # Capped at the apps-namespace LimitRange max (cpu 2 / memory 4Gi per
    # container). All five profile gateways share this one container's budget.
    resources = {
      requests = {
        cpu = "500m";
        memory = "2Gi";
      };
      limits = {
        cpu = "2";
        memory = "4Gi";
      };
    };
    securityContext = commonSecurityContext;
  };

  containers = [ gatewayContainer ];

in
{
  kubernetes.resources.configMaps."${cliWrapper.name}" = {
    metadata.namespace = namespace;
    data.hermes = ''
      #!/bin/sh
      if [ "$(id -u)" = "0" ]; then
        exec gosu 10000:2002 /opt/hermes/.venv/bin/hermes "$@"
      fi
      exec /opt/hermes/.venv/bin/hermes "$@"
    '';
  };

  # Run directly as the hermes runtime user. With per-profile HERMES_HOME on
  # CephFS, root without DAC capabilities cannot traverse the 0700 profile dirs.
  kubernetes.resources.deployments."${name}-gateway" = {
    metadata = {
      name = "${name}-gateway";
      inherit namespace;
      labels = {
        app = name;
        component = "gateway";
      };
    };
    spec = {
      replicas = 1;
      strategy.type = "Recreate";
      selector.matchLabels = {
        app = name;
        component = "gateway";
      };
      template = {
        metadata.labels = {
          app = name;
          component = "gateway";
        };
        spec = {
          securityContext = podSecurityContext;
          terminationGracePeriodSeconds = 60;
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          initContainers = [
            {
              name = "fix-profile-permissions";
              inherit image;
              command = [
                "/bin/sh"
                "-c"
                ''
                  # Profile HOMEs: hermes creates each /opt/data/profiles/<p>
                  # as 0700 owned by the runtime uid, which locks the SMB client
                  # (authenticated as GID 2002, not the dir owner) out of that
                  # profile's folder — the cause of "sometimes I lose access".
                  # Normalize ownership + group access so every profile is
                  # reachable. Only touches wrong entries, so it stays fast.
                  for d in /opt/data/profiles/*/; do
                    [ -d "$d" ] || continue
                    find "$d" ! -user 10000 -exec chown 10000 {} + 2>/dev/null || true
                    find "$d" ! -group 2002 -exec chgrp 2002 {} + 2>/dev/null || true
                    find "$d" -type d ! -perm -2070 -exec chmod g+rwxs {} + 2>/dev/null || true
                    find "$d" -type f ! -perm -060 -exec chmod g+rw {} + 2>/dev/null || true
                  done
                  # Guarantee read/write for everything in the unified "homelab" group
                  # (GID 2002 — the agents' primary gid and the host user's group, and
                  # what other pods join via supplementalGroups). setgid on dirs so new
                  # entries inherit the group; group-writable. Only touches wrong
                  # entries, so it stays fast on large trees.
                  for d in /shared/*/; do
                    [ -d "$d" ] || continue
                    find "$d" ! -group 2002 -exec chgrp 2002 {} + 2>/dev/null || true
                    find "$d" -type d ! -perm -2070 -exec chmod g+rwxs {} + 2>/dev/null || true
                    find "$d" -type f ! -perm -060 -exec chmod g+rw {} + 2>/dev/null || true
                  done
                ''
              ];
              volumeMounts = dataVolumeMounts;
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
                capabilities.add = [ "DAC_OVERRIDE" ];
                capabilities.drop = [ ];
              };
            }
          ];
          containers = containers;
          volumes = dataVolumes ++ [
            {
              name = cliWrapper.volumeName;
              configMap = {
                name = cliWrapper.name;
                defaultMode = 493;
              };
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.deployments."${name}-dashboard" = {
    metadata = {
      name = "${name}-dashboard";
      inherit namespace;
      labels = {
        app = name;
        component = "dashboard";
      };
    };
    spec = {
      replicas = 1;
      strategy.type = "Recreate";
      selector.matchLabels = {
        app = name;
        component = "dashboard";
      };
      template = {
        metadata.labels = {
          app = name;
          component = "dashboard";
        };
        spec = {
          securityContext = podSecurityContext;
          terminationGracePeriodSeconds = 30;
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          containers = [
            {
              name = "dashboard";
              inherit image;
              imagePullPolicy = "IfNotPresent";
              command = [
                "/bin/sh"
                "-c"
                "umask 0002; exec /opt/hermes/.venv/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure"
              ];
              ports = [
                {
                  name = "http";
                  containerPort = 9119;
                  protocol = "TCP";
                }
              ];
              env = [
                {
                  name = "HERMES_UID";
                  value = "10000";
                }
                {
                  name = "HERMES_GID";
                  value = "2002";
                }
                {
                  name = "HERMES_HOME";
                  value = "/opt/data";
                }
                {
                  name = "TZ";
                  value = homelab.timeZone;
                }
              ]
              ++ [
                {
                  name = "PATH";
                  value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes/.venv/bin";
                }
              ];
              envFrom = envFromSecret;
              volumeMounts = dataVolumeMounts ++ [
                {
                  name = cliWrapper.volumeName;
                  mountPath = cliWrapper.mountPath;
                  subPath = "hermes";
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "1Gi";
                };
              };
              securityContext = commonSecurityContext;
              readinessProbe = {
                tcpSocket.port = 9119;
                initialDelaySeconds = 15;
                periodSeconds = 10;
              };
              livenessProbe = {
                tcpSocket.port = 9119;
                initialDelaySeconds = 60;
                periodSeconds = 30;
              };
            }
          ];
          volumes = dataVolumes ++ [
            {
              name = cliWrapper.volumeName;
              configMap = {
                name = cliWrapper.name;
                defaultMode = 493;
              };
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.services."${name}-dashboard" = {
    metadata = {
      name = "${name}-dashboard";
      inherit namespace;
      labels.app = name;
    };
    spec = {
      type = "ClusterIP";
      selector = {
        app = name;
        component = "dashboard";
      };
      ports = [
        {
          name = "http";
          port = 9119;
          targetPort = 9119;
          protocol = "TCP";
        }
      ];
    };
  };

  kubernetes.resources.ingresses."${name}-dashboard" = {
    metadata = {
      name = "${name}-dashboard";
      inherit namespace;
      annotations = {
        "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
      };
    };
    spec = {
      ingressClassName = kubenix.lib.defaultIngressClass;
      tls = [
        {
          hosts = [ (kubenix.lib.domainFor "hermes") ];
          secretName = kubenix.lib.defaultTLSSecret;
        }
      ];
      rules = [
        {
          host = kubenix.lib.domainFor "hermes";
          http.paths = [
            {
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "${name}-dashboard";
                port.number = 9119;
              };
            }
          ];
        }
      ];
    };
  };

  kubernetes.resources.clusterRoles."${name}-readonly" = {
    metadata.labels.app = name;
    rules = [
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "pods/log"
          "pods/status"
          "nodes"
          "services"
          "endpoints"
          "configmaps"
          "events"
          "namespaces"
          "persistentvolumes"
          "persistentvolumeclaims"
        ];
        verbs = [
          "get"
          "list"
          "watch"
          "delete"
        ];
      }
      {
        apiGroups = [ "apps" ];
        resources = [
          "deployments"
          "statefulsets"
          "daemonsets"
          "replicasets"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
    ];
  };

  kubernetes.resources.clusterRoleBindings."${name}-readonly" = {
    metadata.labels.app = name;
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "${name}-readonly";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "default";
        namespace = namespace;
      }
    ];
  };
}

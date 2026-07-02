{ kubenix, homelab, ... }:

let
  name = "hermes-agent";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "docker.io/nousresearch/hermes-agent:v2026.7.1@sha256:5fc62636d9f88dd1edde26aabfdcbac3060af559104d8cbbf5736b579828becf";
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

  # Common env vars shared across all gateway containers.
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
    # Shared config via Managed Scope: /opt/data/managed/config.yaml is overlaid
    # (leaf-level, managed wins) on top of every profile's config.yaml, so all 5
    # profiles share one config. Per-profile config.yaml carries only the keys
    # that must differ (model.default, skills.disabled; + kira whatsapp, + spike
    # kanban). Kept out of /opt/data itself so host-only keys aren't pinned.
    {
      name = "HERMES_MANAGED_DIR";
      value = "/opt/data/managed";
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
    # Route x_search (Hermes built-in X/Twitter search) through OpenRouter
    # instead of xAI directly. OpenRouter proxies xAI's /responses endpoint and
    # forwards the x_search tool type to xAI's server, so the agent gets real
    # X firehose citations without needing a separate XAI_API_KEY.
    {
      name = "XAI_API_KEY";
      valueFrom.secretKeyRef = {
        name = "${name}-env";
        key = "OPENROUTER_API_KEY";
      };
    }
    {
      name = "XAI_BASE_URL";
      value = "https://openrouter.ai/api/v1";
    }
    {
      name = "AGENT_BROWSER_ENGINE";
      value = "chrome";
    }
    {
      name = "BROWSER_CDP_URL";
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
    # Pin git commit identity. GIT_AUTHOR_*/GIT_COMMITTER_* env take precedence
    # over any per-workspace `git config user.email`, so agents can't improvise
    # author emails (which previously leaked attribution to unrelated GitHub
    # accounts that happened to own those emails, e.g. hermes@nousresearch.com).
    # Uses the owner's GitHub no-reply address so commits attribute correctly.
    {
      name = "GIT_AUTHOR_NAME";
      value = "José Victor Ferreira";
    }
    {
      name = "GIT_AUTHOR_EMAIL";
      value = "4625612+josevictorferreira@users.noreply.github.com";
    }
    {
      name = "GIT_COMMITTER_NAME";
      value = "José Victor Ferreira";
    }
    {
      name = "GIT_COMMITTER_EMAIL";
      value = "4625612+josevictorferreira@users.noreply.github.com";
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
  gatewayProfiles = [
    {
      profile = "ted";
      profileFlag = "ted";
      matrixSecretKey = "MATRIX_ACCESS_TOKEN";
      whatsapp = false;
    }
    {
      profile = "kira";
      profileFlag = "kira";
      matrixSecretKey = "HERMES_KIRA_MATRIX_ACCESS_TOKEN";
      whatsapp = true;
    }
    {
      profile = "mel";
      profileFlag = "mel";
      matrixSecretKey = "HERMES_MEL_MATRIX_ACCESS_TOKEN";
      whatsapp = false;
    }
    {
      profile = "spike";
      profileFlag = "spike";
      matrixSecretKey = "HERMES_SPIKE_MATRIX_ACCESS_TOKEN";
      whatsapp = false;
      cpuLimit = "125m";
    }
    {
      profile = "luna";
      profileFlag = "luna";
      matrixSecretKey = "HERMES_LUNA_MATRIX_ACCESS_TOKEN";
      whatsapp = false;
      cpuLimit = "125m";
    }
  ];

  gatewayContainer =
    {
      profile,
      profileFlag,
      matrixSecretKey,
      whatsapp,
      cpuLimit ? "500m",
    }:
    let
      containerName = "gateway-${profile}";
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
                        # Bootstrap WhatsApp bridge dependencies if needed
                        if [ "''${WHATSAPP_ENABLED:-false}" = "true" ]; then
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
      cmdArgs =
        if profileFlag != null then
          [
            "/bin/sh"
            "-c"
            ''
              ${bootstrap}
              exec hermes -p ${profileFlag} gateway run
            ''
          ]
        else
          [
            "/bin/sh"
            "-c"
            ''
              ${bootstrap}
              exec gateway run
            ''
          ];
    in
    {
      name = containerName;
      inherit image;
      imagePullPolicy = "IfNotPresent";
      command = cmdArgs;
      env =
        commonEnv
        ++ [
          {
            name = "HOME";
            value = "/opt/data";
          }
          {
            name = "HERMES_HOME";
            value = "/opt/data/profiles/${profile}";
          }
          {
            name = "MATRIX_ACCESS_TOKEN";
            valueFrom.secretKeyRef = {
              name = "${name}-env";
              key = matrixSecretKey;
            };
          }
        ]
        ++ (
          if whatsapp then
            [
              {
                name = "WHATSAPP_ENABLED";
                value = "true";
              }
              {
                name = "WHATSAPP_MODE";
                value = "bot";
              }
              {
                name = "WHATSAPP_ALLOWED_USERS";
                valueFrom.secretKeyRef = {
                  name = "${name}-env";
                  key = "HERMES_KIRA_WHATSAPP_ALLOWED_USERS";
                };
              }
              {
                name = "WHATSAPP_DEBUG";
                value = "true";
              }
            ]
          else
            [ ]
        );
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
          memory = "512Mi";
        };
        limits = {
          cpu = cpuLimit;
          memory = "1Gi";
        };
      };
      securityContext = commonSecurityContext;
    };

  containers = map gatewayContainer gatewayProfiles;

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
                  # Plugins installed via the dashboard land in /opt/data/plugins
                  # (its HERMES_HOME is /opt/data), but per-profile agents scan
                  # $HERMES_HOME/plugins = /opt/data/profiles/<p>/plugins. Link the
                  # shared plugins into every profile so dashboard-installed
                  # backends (e.g. omniroute) are discovered by each agent.
                  # (config still gates which ones actually load via plugins.enabled.)
                  if [ -d /opt/data/plugins ]; then
                    for d in /opt/data/profiles/*/; do
                      [ -d "$d" ] || continue
                      mkdir -p "$d/plugins"
                      for p in /opt/data/plugins/*/; do
                        [ -d "$p" ] || continue
                        ln -sfn "$p" "$d/plugins/$(basename "$p")"
                      done
                    done
                  fi
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
                "umask 0002; exec /opt/hermes/.venv/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open --insecure"
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

{ kubenix, homelab, ... }:

let
  name = "hermes-agent";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "docker.io/nousresearch/hermes-agent:v2026.5.16@sha256:b6e41c155d6bfce5ad83c5d0fec670086db8a43250e4511c9474134be5482d33";
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
  ];
  dataVolumes = [
    {
      name = "hermes-data";
      persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
    }
  ];
  commonSecurityContext = {
    allowPrivilegeEscalation = false;
    # gosu needs SETUID/SETGID to drop from root → UID 10000.
    capabilities = {
      drop = [ "ALL" ];
      add = [
        "SETUID"
        "SETGID"
        "CHOWN"
        "FOWNER"
      ];
    };
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
      name = "HERMES_HOME";
      value = "/opt/data";
    }
    {
      name = "TZ";
      value = homelab.timeZone;
    }
    {
      name = "AGENT_BROWSER_ENGINE";
      value = "lightpanda";
    }
    {
      name = "AGENT_BROWSER_ENDPOINT";
      value = "http://lightpanda.${namespace}.svc.cluster.local:9222";
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
      name = "PATH";
      value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes/.venv/bin";
    }
    {
      name = "PYTHONPATH";
      value = "/opt/data/.local/lib/python3.13/site-packages";
    }
  ];

  # Per-profile gateway containers.
  gatewayProfiles = [
    {
      profile = "ted";
      profileFlag = "ted";
      matrixSecretKey = "MATRIX_ACCESS_TOKEN";
    }
    {
      profile = "kira";
      profileFlag = "kira";
      matrixSecretKey = "HERMES_KIRA_MATRIX_ACCESS_TOKEN";
    }
    {
      profile = "mel";
      profileFlag = "mel";
      matrixSecretKey = "HERMES_MEL_MATRIX_ACCESS_TOKEN";
    }
  ];

  gatewayContainer =
    {
      profile,
      profileFlag,
      matrixSecretKey,
    }:
    let
      containerName = "gateway-${profile}";
      cmdArgs =
        if profileFlag != null then
          [
            "-p"
            profileFlag
            "gateway"
            "run"
          ]
        else
          [
            "gateway"
            "run"
          ];
    in
    {
      name = containerName;
      inherit image;
      imagePullPolicy = "IfNotPresent";
      args = cmdArgs;
      env = commonEnv ++ [
        {
          name = "MATRIX_ACCESS_TOKEN";
          valueFrom.secretKeyRef = {
            name = "${name}-env";
            key = matrixSecretKey;
          };
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
        };
      };
      securityContext = commonSecurityContext // {
        runAsUser = 0;
      };
    };

  containers = map gatewayContainer gatewayProfiles;

in
{
  kubernetes.resources.configMaps."${cliWrapper.name}" = {
    metadata.namespace = namespace;
    data.hermes = ''
      #!/bin/sh
      exec gosu 10000:10000 /opt/hermes/.venv/bin/hermes "$@"
    '';
  };

  # No init container: CephFS rejects chown from unprivileged-capability containers.
  # The hermes entrypoint runs as root (UID 0), then gosu-drops to UID 10000.
  # Its internal chown tolerates failure on CephFS (continues with warning).
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
          terminationGracePeriodSeconds = 60;
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          containers = [
            {
              name = "gateway";
              inherit image;
              imagePullPolicy = "IfNotPresent";
              args = [
                "gateway"
                "run"
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
                {
                  name = "AGENT_BROWSER_ENGINE";
                  value = "lightpanda";
                }
                {
                  name = "AGENT_BROWSER_ENDPOINT";
                  value = "http://lightpanda.${namespace}.svc.cluster.local:9222";
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
              ]
              ++ [
                {
                  name = "PATH";
                  value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes/.venv/bin";
                }
                {
                  name = "PYTHONPATH";
                  value = "/opt/data/.local/lib/python3.13/site-packages";
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
                };
              };
              securityContext = commonSecurityContext // {
                runAsUser = 0;
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
          terminationGracePeriodSeconds = 30;
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          containers = [
            {
              name = "dashboard";
              inherit image;
              imagePullPolicy = "IfNotPresent";
              args = [
                "dashboard"
                "--host"
                "0.0.0.0"
                "--port"
                "9119"
                "--no-open"
                "--insecure"
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
                  memory = "512Mi";
                };
              };
              securityContext = commonSecurityContext // {
                runAsUser = 0;
              };
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
}

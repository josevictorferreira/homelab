{ homelab, ... }:

let
  app = "velox";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 8080;
  secretName = "${app}-config";

  # Velox refuses to start on an unknown key, a bad base_url, or a combo target
  # that names an undeclared model, so a typo here fails the pod immediately
  # rather than degrading at request time.
  #
  # This file holds no credentials by design: every *_env key names an
  # environment variable supplied by the ${secretName} Secret. That is why this
  # is a plain ConfigMap and not a .enc.nix file.
  #
  # The TOML lives alongside this module; it mirrors the tested
  # examples/omniroute-port.toml in the Velox repo.
  veloxConfig = builtins.readFile ./velox.toml;

  # A subPath-mounted ConfigMap is never refreshed by the kubelet, and a
  # ConfigMap-only change leaves the Deployment spec untouched, so Flux would
  # apply the new config while the running pod keeps the old one indefinitely
  # (see apps/AGENTS.md). Hashing the content into a pod annotation makes any
  # config edit roll the Deployment.
  configHash = builtins.hashString "sha256" veloxConfig;

  # --- OAuth credential agent sidecar ---------------------------------------
  #
  # velox-oauth-agent owns the OAuth flow and refresh for the subscription
  # providers (see docs/oauth-operator-runbook.md in the velox repo). It runs
  # as a second container in this pod, publishing access-token and metadata
  # files into the shared oauth-runtime emptyDir; Velox mounts that dir
  # read-only and re-reads it at dispatch.
  #
  # The agent config ships with ZERO credentials: the sidecar starts, serves
  # health, and does nothing until the operator adds an approved
  # [credentials.*] entry (Milestone-0 authorization prerequisites) and logs
  # in from a workstation. Enable a provider in velox.toml only after login —
  # Velox fails startup on a missing credential_file.
  agentApp = "velox-oauth-agent";
  agentPort = 8081;
  oauthStateSecret = "velox-oauth-state";

  # NOTE: the durable-state Secret ${oauthStateSecret} is deliberately NOT a
  # kubenix resource. The agent writes it with resourceVersion
  # compare-and-swap; a GitOps-managed Secret would fight those writes on
  # every reconcile. Bootstrap it manually per the runbook:
  #   kubectl -n ${namespace} create secret generic ${oauthStateSecret} --from-literal=.bootstrap=1
  agentConfig = ''
    # velox-oauth-agent config. Zero credentials: inert until the operator
    # adds approved [credentials.*] entries. Never put secret values here;
    # client_secret_env would name an env var injected from ${secretName}.
    #
    # Credential shapes and the login/rollout procedure:
    # docs/oauth-operator-runbook.md in the velox repo.

    [store]
    secret_name = "${oauthStateSecret}"
    namespace = "${namespace}"

    [server]
    # Pod probes reach this over the pod IP, so it cannot stay loopback; the
    # metrics surface carries no sensitive data (provider/state labels only).
    bind = "0.0.0.0:${toString agentPort}"

    [runtime]
    dir = "/oauth-runtime"
  '';
  agentConfigHash = builtins.hashString "sha256" agentConfig;
in
{
  kubernetes.resources.configMaps."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    data."velox.toml" = veloxConfig;
  };

  kubernetes.resources.configMaps."${agentApp}-config" = {
    metadata = {
      name = "${agentApp}-config";
      inherit namespace;
    };
    data."agent.toml" = agentConfig;
  };

  # Dedicated identity for the agent. The pod runs under this ServiceAccount
  # (the only identity the agent needs), with automountServiceAccountToken
  # disabled pod-wide and the token projected only into the agent container,
  # so the Velox container holds no Kubernetes credentials at all.
  kubernetes.resources.serviceAccounts.${agentApp} = {
    metadata = {
      name = agentApp;
      inherit namespace;
    };
  };

  # Least privilege: read and CAS-write exactly the one durable-state Secret.
  kubernetes.resources.roles.${agentApp} = {
    metadata = {
      name = agentApp;
      inherit namespace;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [ "secrets" ];
        resourceNames = [ oauthStateSecret ];
        verbs = [
          "get"
          "patch"
          "update"
        ];
      }
    ];
  };

  kubernetes.resources.roleBindings.${agentApp} = {
    metadata = {
      name = agentApp;
      inherit namespace;
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = agentApp;
        inherit namespace;
      }
    ];
    roleRef = {
      kind = "Role";
      name = agentApp;
      apiGroup = "rbac.authorization.k8s.io";
    };
  };

  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace port secretName;
      image = {
        repository = "ghcr.io/josevictorferreira/velox";
        tag = "latest";
        pullPolicy = "Always";
      };
      # Measured at ~2 MiB RSS serving traffic and ~10 MiB across 16 concurrent
      # streams; memory tracks connection count, not tokens streamed.
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "256Mi";
        };
      };
      values = {
        defaultPodOptions.imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];

        # Must exceed shutdown_drain_ms + shutdown_grace_ms (10s + 30s) or the
        # kubelet SIGKILLs mid-drain and severs in-flight streams.
        defaultPodOptions.terminationGracePeriodSeconds = 45;

        # The pod's identity exists solely for the agent; no token is
        # auto-mounted into any container. The agent gets one via an explicit
        # projected volume (see persistence.agent-sa-token below).
        defaultPodOptions.automountServiceAccountToken = false;

        # The chart's own ServiceAccount stays disabled; the pod runs under
        # the dedicated, least-privilege identity defined above.
        serviceAccount.main.enabled = false;
        controllers.main.serviceAccount.name = agentApp;

        controllers.main.pod.annotations."velox.josevictor.me/config-hash" = configHash;
        controllers.main.pod.annotations."velox.josevictor.me/oauth-agent-config-hash" =
          agentConfigHash;

        controllers.main.containers.main = {
          args = [
            "--config"
            "/etc/velox/velox.toml"
          ];
          probes = {
            # /healthz is pure liveness and never touches an upstream, so a
            # provider outage cannot restart the proxy.
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/healthz";
                  inherit port;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
            };
            # /readyz reports not-ready while draining, which is what pulls this
            # pod out of the LoadBalancer before the listener closes.
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/readyz";
                  inherit port;
                };
                initialDelaySeconds = 2;
                periodSeconds = 5;
              };
            };
          };
        };

        controllers.main.containers.${agentApp} = {
          image = {
            repository = "ghcr.io/josevictorferreira/${agentApp}";
            tag = "latest";
            pullPolicy = "Always";
          };
          resources = {
            requests = {
              cpu = "25m";
              memory = "32Mi";
            };
            limits = {
              cpu = "500m";
              memory = "128Mi";
            };
          };
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 65532;
            runAsGroup = 65532;
            readOnlyRootFilesystem = true;
            allowPrivilegeEscalation = false;
            capabilities.drop = [ "ALL" ];
          };
          probes = {
            # Liveness only. The agent's /readyz deliberately stays OUT of pod
            # readiness: an OAuth outage must never take the proxy out of
            # service (Velox falls back per combo instead).
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/healthz";
                  port = agentPort;
                };
                initialDelaySeconds = 5;
                periodSeconds = 15;
              };
            };
          };
          # When a credential uses a confidential client, inject its secret as
          # an env var here from the sops-managed ${secretName} Secret, e.g.:
          # env.ANTIGRAVITY_CLIENT_SECRET.valueFrom.secretKeyRef = {
          #   name = secretName; key = "ANTIGRAVITY_CLIENT_SECRET";
          # };
        };

        persistence.config = {
          enabled = true;
          type = "configMap";
          name = "${app}-config";
          advancedMounts.main.main = [
            {
              path = "/etc/velox/velox.toml";
              subPath = "velox.toml";
              readOnly = true;
            }
          ];
          items = [
            {
              key = "velox.toml";
              path = "velox.toml";
            }
          ];
        };

        # Shared token/metadata handoff: written 0600 + atomic rename by the
        # agent, read at dispatch time by Velox. Ephemeral by design — the
        # agent republishes from durable state after any pod restart.
        persistence."oauth-runtime" = {
          enabled = true;
          type = "emptyDir";
          advancedMounts.main = {
            main = [
              {
                path = "/etc/velox/oauth-runtime";
                readOnly = true;
              }
            ];
            ${agentApp} = [
              {
                path = "/oauth-runtime";
                readOnly = false;
              }
            ];
          };
        };

        persistence."agent-config" = {
          enabled = true;
          type = "configMap";
          name = "${agentApp}-config";
          advancedMounts.main.${agentApp} = [
            {
              path = "/etc/velox-oauth/agent.toml";
              subPath = "agent.toml";
              readOnly = true;
            }
          ];
          items = [
            {
              key = "agent.toml";
              path = "agent.toml";
            }
          ];
        };

        # Replicates the standard service-account projection (token + CA),
        # mounted ONLY into the agent container.
        persistence."agent-sa-token" = {
          enabled = true;
          type = "custom";
          volumeSpec = {
            name = "agent-sa-token";
            projected = {
              defaultMode = 420;
              sources = [
                {
                  serviceAccountToken = {
                    path = "token";
                    expirationSeconds = 3607;
                  };
                }
                {
                  configMap = {
                    name = "kube-root-ca.crt";
                    items = [
                      {
                        key = "ca.crt";
                        path = "ca.crt";
                      }
                    ];
                  };
                }
              ];
            };
          };
          advancedMounts.main.${agentApp} = [
            {
              path = "/var/run/secrets/kubernetes.io/serviceaccount";
              readOnly = true;
            }
          ];
        };
      };
    };
  };
}

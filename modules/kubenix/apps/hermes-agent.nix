{ kubenix, homelab, ... }:

let
  name = "hermes-agent";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/josevictorferreira/hermes-agent:6b09df3@sha256:0a5ce49bc1edc9a8764bb183279c067d88d7160ad3ea71a2648262348a9187f4";
  envFromSecret = [
    { secretRef.name = "${name}-env"; }
  ];
  dataVolumeMounts = [
    {
      name = "hermes-data";
      mountPath = "/opt/data";
      subPath = "hermes";
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
    capabilities.drop = [ "ALL" ];
  };
in
{
  # Init container chowns the CephFS subPath so the hermes user (UID 10000)
  # can write to /opt/data after gosu drops privileges.
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
          initContainers = [
            {
              name = "init-data";
              image = "busybox:1.36";
              command = [
                "sh"
                "-c"
                "mkdir -p /opt/data && chown -R 10000:10000 /opt/data && chmod 0750 /opt/data"
              ];
              volumeMounts = dataVolumeMounts;
              securityContext = {
                runAsUser = 0;
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                capabilities.add = [
                  "CHOWN"
                  "FOWNER"
                ];
              };
            }
          ];
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
                  value = "10000";
                }
                {
                  name = "HERMES_HOME";
                  value = "/opt/data";
                }
              ];
              envFrom = envFromSecret;
              volumeMounts = dataVolumeMounts;
              resources = {
                requests = {
                  cpu = "500m";
                  memory = "1Gi";
                };
                limits = {
                  cpu = "2";
                  memory = "4Gi";
                };
              };
              securityContext = commonSecurityContext // {
                runAsUser = 0;
              };
            }
          ];
          volumes = dataVolumes;
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
          initContainers = [
            {
              name = "wait-data";
              image = "busybox:1.36";
              command = [
                "sh"
                "-c"
                "mkdir -p /opt/data && chown -R 10000:10000 /opt/data && chmod 0750 /opt/data"
              ];
              volumeMounts = dataVolumeMounts;
              securityContext = {
                runAsUser = 0;
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                capabilities.add = [
                  "CHOWN"
                  "FOWNER"
                ];
              };
            }
          ];
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
                  value = "10000";
                }
                {
                  name = "HERMES_HOME";
                  value = "/opt/data";
                }
              ];
              envFrom = envFromSecret;
              volumeMounts = dataVolumeMounts;
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
          volumes = dataVolumes;
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

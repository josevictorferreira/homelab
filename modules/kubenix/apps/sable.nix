{ homelab, ... }:

let
  app = "sable";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/sable";
    tag = "e37e8e4@sha256:f515caeed0d7c0e02bec33edb048583b8ef069d9b98163e13fe4c82cfe9eb2fd";
    pullPolicy = "IfNotPresent";
  };
  port = 8080;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];

  # Static SPA served by Caddy; this file replaces the bundled /app/config.json.
  # Login goes straight to matrix.josevictor.me, which also serves its own
  # .well-known for the josevictor.me server name. GIFs are left out:
  # Sable can only send them through a Matrix media proxy, and tuwunel does not
  # fetch remote media with federation disabled.
  config = {
    productName = "Sable";
    defaultHomeserver = 0;
    homeserverList = [ "matrix.${homelab.domain}" ];
    allowCustomHomeservers = true;
    disableAccountSwitcher = false;
    hideUsernamePasswordFields = false;
    hashRouter = {
      enabled = false;
      basename = "/";
    };
    featuredCommunities = {
      openAsDefault = false;
      spaces = [ ];
      rooms = [ ];
      servers = [ ];
    };
  };

  # A subPath-mounted ConfigMap is never refreshed by the kubelet (see
  # apps/AGENTS.md); hashing the config into a pod annotation rolls the pod.
  configHash = builtins.hashString "sha256" (builtins.toJSON config);
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace image port;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "128Mi";
        };
      };
      config = {
        filename = "config.json";
        mountPath = "/app";
        data = config;
      };
      values = {
        controllers.main.pod.annotations."${app}.${homelab.domain}/config-hash" = configHash;
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main = {
          # The image strips Caddy's file capabilities so it can run with an
          # empty bounding set while listening on :8080.
          securityContext = {
            allowPrivilegeEscalation = false;
            capabilities.drop = [ "ALL" ];
          };
          probes = {
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/";
                  inherit port;
                };
                periodSeconds = 30;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            };
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/";
                  inherit port;
                };
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };
            };
          };
        };
      };
    };
  };
}

{ homelab, ... }:

let
  app = "sable";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/sable";
    tag = "48abdf4@sha256:a7c44398a57aff568c8293368369be8f11bcb637d0e1cfaf5daef9fa5b974569";
    pullPolicy = "IfNotPresent";
  };
  port = 8080;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];

  # Static SPA served by Caddy; this file replaces the bundled /app/config.json.
  # The homeserver is discovered through https://josevictor.me/.well-known/matrix,
  # which tuwunel serves and points at matrix.josevictor.me. GIFs are left out:
  # Sable can only send them through a Matrix media proxy, and tuwunel does not
  # fetch remote media with federation disabled.
  config = {
    productName = "Sable";
    defaultHomeserver = 0;
    homeserverList = [ homelab.domain ];
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
          cpu = "10m";
          memory = "32Mi";
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

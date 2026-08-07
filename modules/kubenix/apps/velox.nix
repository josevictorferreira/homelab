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
in
{
  kubernetes.resources.configMaps."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    data."velox.toml" = veloxConfig;
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
        defaultPodOptions.imagePullSecrets = [{ name = "ghcr-registry-secret"; }];

        # Must exceed shutdown_drain_ms + shutdown_grace_ms (10s + 30s) or the
        # kubelet SIGKILLs mid-drain and severs in-flight streams.
        defaultPodOptions.terminationGracePeriodSeconds = 45;

        controllers.main.pod.annotations."velox.josevictor.me/config-hash" = configHash;

        controllers.main.containers.main = {
          args = [ "--config" "/etc/velox/velox.toml" ];
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

        persistence.config = {
          enabled = true;
          type = "configMap";
          name = "${app}-config";
          globalMounts = [
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
      };
    };
  };
}

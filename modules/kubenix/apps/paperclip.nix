{ homelab, kubenix, ... }:

let
  app = "paperclip";
  namespace = homelab.kubernetes.namespaces.applications;
  secretName = "${app}-env";
  port = 3100;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];
  image = {
    # GHCR tags drop the leading "v" of the GitHub release (v2026.1023.0).
    repository = "ghcr.io/paperclipai/paperclip";
    tag = "2026.1023.0@sha256:40f46940c4612ead131aebe6079cd4651f8cd1434af49f7c621887f4a452a62e";
    pullPolicy = "IfNotPresent";
  };
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace image port secretName;
      waitFor = [ "postgres" ];

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

      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = kubenix.lib.defaultStorageClass;
        size = "10Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            # Everything Paperclip persists (agent workspaces, uploads, local
            # secrets key) lives under PAPERCLIP_HOME.
            path = "/paperclip";
            readOnly = false;
          }
        ];
      };

      values = {
        controllers.main.strategy = "Recreate";
        defaultPodOptions.imagePullSecrets = pullSecrets;
        # Single RWO PVC: hard anti-affinity against the Pi (15GiB SD root
        # cannot hold the ~3GiB image, and its pi-only taint already repels
        # unpinned pods; keep it explicit anyway).
        defaultPodOptions.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 100;
            podAffinityTerm = {
              topologyKey = "kubernetes.io/hostname";
              labelSelector.matchLabels.app = app;
            };
          }
        ];
        defaultPodOptions.securityContext = {
          runAsNonRoot = true;
          runAsUser = 1000;
          runAsGroup = 1000;
          fsGroup = 1000;
          fsGroupChangePolicy = "OnRootMismatch";
        };
        # Upstream ships 90s stop_grace_period so running agents settle before
        # the container dies; give the probe-based shutdown a little slack.
        controllers.main.pod.terminationGracePeriodSeconds = 120;

        controllers.main.containers.main = {
          env = {
            # External CNPG postgres instead of the embedded one.
            PAPERCLIP_MIGRATION_AUTO_APPLY = "true";
            # authenticated + private: login required, served behind Cilium
            # ingress with the wildcard cert, LAN/tailnet only.
            PAPERCLIP_DEPLOYMENT_MODE = "authenticated";
            PAPERCLIP_DEPLOYMENT_EXPOSURE = "private";
            PAPERCLIP_PUBLIC_URL = "https://${kubenix.lib.domainFor app}";
            # Single trusted reverse-proxy hop (Cilium ingress).
            TRUST_PROXY = "1";
            PAPERCLIP_TELEMETRY_DISABLED = "1";
          };
          probes = {
            # /api/liveness is process-only (503 until startup recovery is
            # done): cheap, no SQL, no auth.
            startup = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/api/liveness";
                  inherit port;
                };
                periodSeconds = 10;
                failureThreshold = 36; # 6 min: first boot runs migrations
              };
            };
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/api/liveness";
                  inherit port;
                };
                periodSeconds = 30;
                failureThreshold = 3;
              };
            };
            # /api/health probes the database (503 when unreachable).
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/api/health";
                  inherit port;
                };
                periodSeconds = 15;
                failureThreshold = 4;
              };
            };
          };
        };
      };
    };
  };
}

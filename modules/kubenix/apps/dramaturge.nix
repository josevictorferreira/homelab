{ homelab, kubenix, ... }:

let
  app = "dramaturge";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    repository = "ghcr.io/josevictorferreira/dramaturge";
    tag = "latest";
    pullPolicy = "Always";
  };
  port = 9292;
  secretName = "${app}-config";
  pullSecrets = [{ name = "ghcr-registry-secret"; }];
in
{
  submodules.instances = {
    # Web API — the container ENTRYPOINT runs migrations, then execs the CMD
    # (ruby bin/web → Puma on :9292).
    dramaturge = {
      submodule = "release";
      args = {
        inherit namespace image port secretName;
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "512Mi";
          };
        };
        values = {
          defaultPodOptions.imagePullSecrets = pullSecrets;
          controllers.main.containers.main.probes = {
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/health";
                  port = port;
                };
                initialDelaySeconds = 15;
                periodSeconds = 10;
              };
            };
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/ready";
                  port = port;
                };
                initialDelaySeconds = 5;
                periodSeconds = 5;
              };
            };
          };
        };
      };
    };

    # Background worker — polls the job queue and processes stories through
    # the LLM pipeline. Keeps the container ENTRYPOINT (migrations) via args
    # override so it also migrates on cold starts.
    dramaturge-worker = {
      submodule = "release";
      args = {
        inherit namespace image port secretName;
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "512Mi";
          };
        };
        values = {
          defaultPodOptions.imagePullSecrets = pullSecrets;
          controllers.main.containers.main.args = [ "ruby" "bin/worker" ];
          service.main.type = "ClusterIP";
          ingress.main.enabled = false;
        };
      };
    };
  };
}

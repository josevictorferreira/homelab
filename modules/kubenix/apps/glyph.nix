{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  pullSecrets = [{ name = "ghcr-registry-secret"; }];

  # glyph-v2 (Rust rewrite of the Rails app): a backend serving HTTP, gRPC and
  # gRPC-Web on :3000 (job worker, tickers and boot migrations in-process) and
  # an nginx frontend serving the SPA and reverse-proxying API paths to the
  # backend. Instance names match the `rollout restart deployment/...` targets
  # in the glyph-v2 repo's deploy flakes.
  backendImage = {
    repository = "ghcr.io/josevictorferreira/glyph-v2";
    tag = "latest";
    pullPolicy = "Always";
  };
  frontendImage = {
    repository = "ghcr.io/josevictorferreira/glyph-v2-frontend";
    tag = "latest";
    pullPolicy = "Always";
  };
  backendPort = 3000;
  frontendPort = 8080;
in
{
  submodules.instances = {
    glyph = {
      submodule = "release";
      args = {
        waitFor = [ "postgres" ];
        inherit namespace;
        image = backendImage;
        port = backendPort;
        secretName = "glyph-config";
        resources = {
          requests = {
            cpu = "100m";
            memory = "512Mi";
          };
          # Step runs spawn the Pi agent (Node) as a child process, up to
          # GLYPH_STEP_CONCURRENCY (5) at a time.
          limits = {
            cpu = "2000m";
            memory = "4Gi";
          };
        };
        values = {
          defaultPodOptions.imagePullSecrets = pullSecrets;
          # Browsers reach the backend through the frontend's nginx proxy; the
          # backend itself gets no ingress (the LAN LB IP still allows direct
          # gRPC for grpcurl).
          ingress.main.enabled = false;
          # Health is GET /up: 200 when the database answers.
          controllers.main.containers.main.probes = {
            startup = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/up";
                  port = backendPort;
                };
                initialDelaySeconds = 15;
                periodSeconds = 10;
                failureThreshold = 30;
              };
            };
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                httpGet = {
                  path = "/up";
                  port = backendPort;
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
                  path = "/up";
                  port = backendPort;
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

    glyph-frontend = {
      submodule = "release";
      args = {
        inherit namespace;
        image = frontendImage;
        port = frontendPort;
        resources = {
          requests = {
            cpu = "50m";
            memory = "64Mi";
          };
          limits = {
            cpu = "500m";
            memory = "256Mi";
          };
        };
        values = {
          defaultPodOptions.imagePullSecrets = pullSecrets;
          # nginx template target for the proxied gRPC-Web/artifact routes.
          controllers.main.containers.main.env.GLYPH_BACKEND_URL =
            "http://${kubenix.lib.serviceHostFor "glyph" namespace}:${toString backendPort}";
          # Ingress-only: no LAN LB IP of its own (entry in loadBalancer.services
          # exists only to satisfy the release submodule's eager annotation
          # lookup; like dramaturge-worker, the ClusterIP service keeps the
          # inert lbipam annotations the submodule base merges in).
          service.main.type = "ClusterIP";
          # Keep the public domain on the frontend (the submodule derives it
          # from the instance name, which would be glyph-frontend.josevictor.me).
          ingress.main.hosts = [
            {
              host = "glyph.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  service.name = "glyph-frontend";
                  service.port = frontendPort;
                }
              ];
            }
          ];
          ingress.main.tls = [
            {
              secretName = kubenix.lib.defaultTLSSecret;
              hosts = [ "glyph.${homelab.domain}" ];
            }
          ];
          controllers.main.containers.main.probes = {
            liveness = {
              enabled = true;
              custom = true;
              spec = {
                tcpSocket.port = frontendPort;
                periodSeconds = 30;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
            };
            readiness = {
              enabled = true;
              custom = true;
              spec = {
                tcpSocket.port = frontendPort;
                periodSeconds = 10;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
            };
          };
        };
      };
    };
  };
}

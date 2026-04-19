{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "homelab-bridge";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/homelab-bridge";
        tag = "bd45fe8@sha256:130d3cfad91ee1ac63fbf956d96a89f5bc1e24a2844a9c89259bd146984279c7";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "256Mi";
        };
      };
      secretName = "${app}-env";
      values = {
        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];
        controllers.main.containers.main.env = {
          PORT = "8080";
          MATRIX_SERVER_URL = "http://tuwunel.apps.svc.cluster.local:8008";
          MATRIX_USER = "@homelab-bridge:josevictor.me";
          MATRIX_ROOM_ID = "!d0dYdkGOcX7cchTc4H:josevictor.me";
          MATRIX_LOGIN_TYPE = "m.login.password";
        };

        # Tailscale Funnel sidecar — exposes webhook to public internet
        controllers.main.containers.tailscale = {
          image = {
            repository = "tailscale/tailscale";
            tag = "latest";
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
            capabilities.add = [
              "NET_ADMIN"
              "NET_RAW"
            ];
          };
          env = {
            TS_AUTHKEY = {
              valueFrom.secretKeyRef = {
                name = "${app}-env";
                key = "TS_AUTHKEY";
              };
            };
            TS_HOSTNAME = "homelab-bridge";
            TS_USERSPACE = "false";
            TS_STATE_DIR = "/var/lib/tailscale";
            TS_ACCEPT_DNS = "false";
            TS_AUTH_ONCE = "true";
            TS_SERVE_CONFIG = "/etc/tailscale/serve.json";
          };
        };

        persistence = {
          # Persistent state for Tailscale node identity
          tailscale-state = {
            type = "persistentVolumeClaim";
            storageClass = "rook-ceph-block";
            size = "1Gi";
            accessMode = "ReadWriteOnce";
            advancedMounts.main.tailscale = [ { path = "/var/lib/tailscale"; } ];
          };
          # Serve config for Funnel (proxies 443 → localhost:8080)
          serve-config = {
            type = "configMap";
            name = "${app}-serve-config";
            advancedMounts.main.tailscale = [
              {
                path = "/etc/tailscale";
                readOnly = true;
              }
            ];
          };
          # /dev/net/tun for Tailscale networking
          dev-tun = {
            type = "hostPath";
            hostPath = "/dev/net/tun";
            advancedMounts.main.tailscale = [ { path = "/dev/net/tun"; } ];
          };
        };
      };
    };
  };

  # Tailscale Funnel serve config — proxies HTTPS 443 to localhost:8080
  # ${TS_CERT_DOMAIN} is substituted at runtime by containerboot
  kubernetes.resources.configMaps."${app}-serve-config" = {
    metadata.namespace = namespace;
    data."serve.json" = ''
      {
        "TCP": { "443": { "HTTPS": true } },
        "Web": {
          "''${TS_CERT_DOMAIN}:443": {
            "Handlers": {
              "/": { "Proxy": "http://127.0.0.1:8080" }
            }
          }
        },
        "AllowFunnel": {
          "''${TS_CERT_DOMAIN}:443": true
        }
      }
    '';
  };
}

{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
  pvcName = "cephfs-shared-storage";
in
{
  kubernetes = {
    helm.releases."qbittorrent" = {
      chart = kubenix.lib.helm.fetch
        {
          chartUrl = "oci://tccr.io/truecharts/qbittorrent";
          chart = "qbittorrent";
          version = "23.3.2";
          sha256 = "sha256-YzN+udEKXR4P73M3sQ6RkRlLhNUunD/jv8C9Ve+Qsoo=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = k8s.namespaces.applications;
      values = {
        image = {
          repository = "ghcr.io/home-operations/qbittorrent";
          tag = "5.1.0@sha256:1cd84c74d3c7ccb7d2edb43fec4cdd2306f6ca30b7e85efd762fa476e1470fba";
          pullPolicy = "IfNotPresent";
        };
        qbitportforwardImage = {
          repository = "docker.io/mjmeli/qbittorrent-port-forward-gluetun-server";
          tag = "latest@sha256:67d0d21ed792cf80716d4211e7162b6d375af5c12f3cf096c9032ad705dddaa8";
          pullPolicy = "IfNotPresent";
        };
        securityContext = {
          fsGroup = 65534;
          container = {
            fsGroup = 65534;
            runAsUser = 65534;
            runAsGroup = 65534;
            readOnlyRootFilesystem = false;
          };
        };

        qbitportforward.enabled = false;

        service = {
          main = kubenix.lib.serviceIpFor "qbittorrent" // {
            ports.main.port = 80;
            ports.main.targetPort = 8080;
          };
          torrent = {
            enabled = true;
            ports.torrent = {
              enabled = true;
              part = 62657;
              protocol = "tcp";
            };
            ports.torrentudp = {
              enabled = true;
              part = 62657;
              protocol = "udp";
            };
          };
          gluetun = {
            enabled = true;
            type = "ClusterIP";
            ports.gluetun = {
              enabled = true;
              part = 8080;
              targetPort = 8080;
              protocol = "http";
            };
          };
        };

        persistence = {
          config = {
            enabled = true;
            mountPath = "/config";
            size = "1Gi";
            storageClass = "rook-ceph-block";
            targetSelector = {
              main = {
                main = { mountPath = "/config"; };
                exportarr = { mountPath = "/config"; readOnly = false; };
              };
            };
          };
          shared = {
            enabled = true;
            type = "pvc";
            existingClaim = pvcName;
            mountPath = "/downloads";
            targetSelector = {
              main = {
                main = { mountPath = "/downloads"; readOnly = false; };
              };
            };
          };
        };

        ingress.main = {
          enabled = true;
          primary = true;
          ingressClassName = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          hosts = [
            {
              host = "qbittorrent.${homelab.domain}";
              paths = [ {
                path = "/";
                pathType = "Prefix";
              } ];
            }
          ];
          tls = [
            {
              hosts = [
                "qbittorrent.${homelab.domain}"
              ];
              secretName = "wildcard-tls";
            }
          ];
          integrations.traefik.enabled = false;
        };

        portal.open.enabled = true;

        workload = {
          main.podSpec = {
            containers = {
              main = {
                env = {
                  DOCKER_MODS = "ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest";
                  QBT_WEBUI_PORT = "8080";
                  QBT_TORRENTING_PORT = "62657";
                };
              };
            };
          };
          qbitportforward = {
            enabled = true;
            type = "Deployment";
            strategy = "RollingUpdate";
            replicas = 1;
            podSpec.containers.qbitportforward = {
              primary = true;
              enabeld = true;
              imageSelector = "qbitportforwardImage";
              probes.liveness.enabled = false;
              probes.readiness.enabled = false;
              probes.startup.enabled = false;
              env = {
                DOCKER_MODS = "ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest";
                QBT_ADDR = "http://localhost:8080";
                GTN_ADDR = "http://localhost:8000";
              };
            };
          };
        };

        addons.vpn = {
          type = "gluetun";
          killSwitch = true;
          envFrom = [ { secretRef.name = "gluetun-vpn-credentials"; } ];
        };

      };
    };
  };
}

{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
  pvcName = "cephfs-shared-storage-downloads";
  namespace = k8s.namespaces.applications;
  torrentingPort = 62657;
  vueTorrentInstallScript = ''
    set -e
    echo "Creating config directory"
    cd /config
    echo "Downloading VueTorrent"
    curl -L -o vuetorrent.zip https://github.com/VueTorrent/VueTorrent/releases/download/v2.29.0/vuetorrent.zip
    echo "Removing old VueTorrent files"
    rm -rf /config/webui
    echo "Extracting VueTorrent"
    unzip vuetorrent.zip -d /config/webui
    echo "Removing unused files"
    rm vuetorrent.zip
    echo "VueTorrent installed"
  '';
  qbtImage = {
    repository = "ghcr.io/home-operations/qbittorrent";
    tag = "5.1.2@sha256:9dd0164cc23e9c937e0af27fd7c3f627d1df30c182cf62ed34d3f129c55dc0e8";
    pullPolicy = "IfNotPresent";
  };
in
{
  kubernetes = {
    helm.releases."qbittorrent" = {
      chart = kubenix.lib.helm.fetch
        {
          chartUrl = "oci://tccr.io/truecharts/qbittorrent";
          chart = "qbittorrent";
          version = "23.3.2";
          sha256 = "sha256-Rks81hetW/b29Dg0PmmresvCuGL3cVuu4leTTZjwSIc=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        image = qbtImage;
        qbitportforwardImage = {
          repository = "docker.io/mjmeli/qbittorrent-port-forward-gluetun-server";
          tag = "latest@sha256:4bd94ad0d289d3d52facdcb708a019e693c8df41e386f6aee80b870fa90baeec";
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

        qbitportforward = {
          enabled = false;
        };

        service = {
          main = kubenix.lib.plainServiceFor "qbittorrent" // {
            ports.main.port = 80;
            ports.main.targetPort = 8080;
          };
          torrent = {
            enabled = true;
            ports.torrent = {
              enabled = true;
              part = torrentingPort;
              protocol = "tcp";
            };
            ports.torrentudp = {
              enabled = true;
              part = torrentingPort;
              protocol = "udp";
            };
          };
          gluetun = {
            enabled = true;
            type = "ClusterIP";
            ports.gluetun = {
              enabled = true;
              part = 8000;
              targetPort = 8000;
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
                main = { mountPath = "/config"; readOnly = false; };
                "install-vuetorrent" = { mountPath = "/config"; readOnly = false; };
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
          "qbittorrent-configs" = {
            enabled = true;
            type = "configmap";
            objectName = "qbittorrent-config";
            expandObjectName = false;
            targetSelector = {
              main = {
                main-conf = { mountPath = "/config/qBittorrent/qBittorrent.conf"; subPath = "qBittorrent.conf"; readOnly = false; };
                main-categories = { mountPath = "/config/qBittorrent/categories.json"; subPath = "categories.json"; readOnly = false; };
                main-watch = { mountPath = "/config/qBittorrent/watched_folders.json"; subPath = "watched_folders.json"; readOnly = false; };
              };
            };
          };
        };

        ingress.main = kubenix.lib.ingressDomainForService "qbittorrent" // {
          integrations.traefik.enabled = false;
        };

        portal.open.enabled = true;

        workload = {
          main.podSpec = {
            initContainers = {
              "install-vuetorrent" = {
                type = "init";
                enabled = true;
                image = qbtImage;
                command = [ "sh" "-c" ];
                args = [ vueTorrentInstallScript ];
              };
            };
            containers = {
              main = {
                probes.liveness.enabled = false;
                probes.readiness.enabled = false;
                probes.startup.enabled = false;
                env = {
                  QBT_WEBUI_PORT = "8080";
                  QBT_TORRENTING_PORT = "${toString torrentingPort}";
                };
              };
            };
          };
          qbitportforward = {
            enabled = true;
            type = "Deployment";
            strategy = "RollingUpdate";
            replicas = 1;
            podSpec.restartPolicy = "Always";
            podSpec.containers.qbitportforward = {
              primary = true;
              enabeld = true;
              imageSelector = "qbitportforwardImage";
              probes.liveness.enabled = false;
              probes.readiness.enabled = false;
              probes.startup.enabled = false;
              env = {
                QBT_ADDR = "http://localhost:8080";
                GTN_ADDR = "http://localhost:8000";
              };
              command = "/usr/src/app/main.sh";
            };
          };
        };

        addons.gluetun = {
          enabled = true;
          killSwitch = true;
          container.env = {
            FIREWALL = "on";
            FIREWALL_INPUT_PORTS = "8080,${toString torrentingPort}";
          };
          container.envFrom = [
            {
              secretRef.name = "gluetun-vpn-credentials";
              secretRef.expandObjectName = false;
            }
          ];
        };

      };
    };
  };
}

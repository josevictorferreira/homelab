{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
  pvcName = "cephfs-apps-shared-storage";
  namespace = k8s.namespaces.applications;
  torrentingPort = 62657;
  qbtUsername = "admin";
  qbtPassword = "adminadmin";
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
        image = {
          repository = "lscr.io/linuxserver/qbittorrent";
          tag = "5.1.2@sha256:d464a92d5656f1fa66baafe610a06a6cafd4bdf900a245e6f20b220f281b456d";
          pullPolicy = "IfNotPresent";
        };
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
          };
        };

        qbitportforward = {
          enabled = false;
          QBT_USERNAME = qbtUsername;
          QBT_PASSWORD = qbtPassword;
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
                main = { mountPath = "/config";  readOnly = false; };
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

        ingress.main = kubenix.lib.ingressDomainForService "qbittorrent" // {
          integrations.traefik.enabled = false;
        };

        portal.open.enabled = true;

        workload = {
          main.podSpec = {
            containers = {
              main = {
                probes.liveness.enabled = false;
                probes.readiness.enabled = false;
                probes.startup.enabled = false;
                ports = {
                  main = { containerPort = 8080; };
                  torrent = { containerPort = torrentingPort; };
                  torrentudp = { containerPort = torrentingPort; protocol = "UDP"; };
                };
                env = {
                  PUID  = "65534";
                  PGID  = "65534";
                  DOCKER_MODS = "ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest";
                  WEBUI_PORT = "8080";
                  TORRENTING_PORT = toString torrentingPort;
                  # QBT_WEBUI_PORT = "8080";
                  # QBT_TORRENTING_PORT = "${toString torrentingPort}";
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
                QBT_USERNAME = qbtUsername;
                QBT_PASSWORD = qbtPassword;
              };
              command = "/usr/src/app/main.sh";
            };
          };
        };

        addons.gluetun = {
          enabled = true;
          killSwitch = true;
          container.env = {
            QBT_USERNAME = qbtUsername;
            QBT_PASSWORD = qbtPassword;
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

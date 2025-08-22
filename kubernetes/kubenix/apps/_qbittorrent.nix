{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
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
                exportarr = { mountPath = "/config"; readOnly = true; };
              };
            };
          };
          "prowlarr-custom-definitions" = {
            enabled = true;
            type = "secret";
            mountPath = "/config/Definitions/Custom";
            objectName = "prowlarr-custom-definitions";
            expandObjectName = false;
            optional = false;
            defaultMode = "0777";
            items = [
              { key = "custom-indexer"; path = "custom-indexer.yml"; }
            ];
            targetSelector = {
              main = {
                main = { mountPath = "/config/Definitions/Custom"; };
                exportarr = { mountPath = "/config/Definitions/Custom"; readOnly = true; };
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
            { host = "prowlarr.${homelab.domain}"; }
          ];
          tls = [
            {
              hosts = [
                "prowlarr.${homelab.domain}"
              ];
              secretName = "wildcard-tls";
            }
          ];
        };

        workload.main.podSpec = {
          containers = {
            main = {
              probes = {
                liveness = { path = "/ping"; };
                readiness = { path = "/ping"; };
                startup = { type = "tcp"; };
              };
              env = {
                PROWLARR__SERVER__PORT = "9696";
                PROWLARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
                PROWLARR__APP__THEME = "dark";
                PROWLARR__APP__INSTANCENAME = "Prowlarr";
                PROWLARR__LOG__LEVEL = "info";
                PROWLARR__UPDATE__BRANCH = "develop";
              };
            };
            exportarr = {
              enabled = true;
              imageSelector = "exportarrImage";
              args = [ "prowlarr" ];
              probes = {
                liveness = { enabled = true; type = "http"; path = "/healthz"; port = 9697; };
                readiness = { enabled = true; type = "http"; path = "/healthz"; port = 9697; };
                startup = { enabled = true; type = "http"; path = "/healthz"; port = 9697; };
              };
              env = {
                INTERFACE = "0.0.0.0";
                PORT = "9697";
                URL = "http://localhost:9696";
                CONFIG = "/config/config.xml";
              };
            };
          };
        };

      };
    };
  };
}

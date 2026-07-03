{ kubenix, homelab, pkgs, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "home-assistant";
  domain = "hass.${homelab.domain}";

  hacsVersion = "2.0.5";
  hacsZipUrl = "https://github.com/hacs/integration/releases/download/${hacsVersion}/hacs.zip";
  hacsZipHash = "sha256-iMomioxH7Iydy+bzJDbZxt6BX31UkCvqhXrxYFQV8Gw=";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://pajikos.github.io/home-assistant-helm-chart";
        chart = "home-assistant";
        version = "0.3.68";
        sha256 = "sha256-/YUEnJAaH6Ea1IeGmaHy2zqdr8nN3xPp11eczVIzrXY=";
      };
      noHooks = true;
      inherit namespace;

      values = {
        replicaCount = 1;

        image = {
          repository = "ghcr.io/home-assistant/home-assistant";
          tag = "2026.7.0";
          pullPolicy = "IfNotPresent";
        };

        controller = {
          type = "StatefulSet";
        };

        envFrom = [
          {
            secretRef = {
              name = "home-assistant-secret";
            };
          }
        ];

        initContainers = [
          {
            name = "install-hacs";
            image = "busybox:1.37";
            imagePullPolicy = "IfNotPresent";
            command = [
              "sh"
              "-c"
              ''
                set -e
                mkdir -p /config/custom_components
                if [ ! -d /config/custom_components/hacs ]; then
                  echo "Installing HACS ${hacsVersion}..."
                  wget -q ${hacsZipUrl} -O /tmp/hacs.zip
                  unzip -q /tmp/hacs.zip -d /config/custom_components/hacs
                  echo "HACS installed"
                else
                  echo "HACS already present, skipping"
                fi
              ''
            ];
            volumeMounts = [
              {
                name = "home-assistant";
                mountPath = "/config";
              }
            ];
          }
        ];

        service = {
          type = "ClusterIP";
          port = 8080;
        };

        ingress = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          annotations = {
            "cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
          };
          hosts = [
            {
              host = domain;
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [ domain ];
              secretName = kubenix.lib.defaultTLSSecret;
            }
          ];
        };

        persistence = {
          enabled = true;
          accessMode = "ReadWriteOnce";
          size = "10Gi";
          storageClass = kubenix.lib.defaultStorageClass;
        };

        configuration = {
          enabled = true;
          trusted_proxies = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "127.0.0.0/8"
          ];
        };
      };
    };
  };
}

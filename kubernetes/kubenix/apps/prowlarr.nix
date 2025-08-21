{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
in
{
  kubernetes = {
    helm.releases."pihole" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "oci://tccr.io/truecharts/prowlarr";
          chart = "prowlarr";
          version = "20.4.2";
          sha256 = "sha256-nhvifpDdM8MoxF43cJAi6o+il2BbHX+udVAvvm1PukM=";
        };
      includeCRDs = false;
      noHooks = true;
      namespace = k8s.namespaces.applications;
      values = {
        image = {
          repository = "ghcr.io/home-operations/prowlarr";
          tag = "2.0.0.5094@sha256:5b890c19bf39a1ca3d889d2b8a6f6a9f1bfa2f63ad51d700f64fd2bd11eec089";
          pullPolicy = "IfNotPresent";
        };
        exportarrImage = {
          repository = "ghcr.io/onedr0p/exportarr";
          tag = "v2.2.0@sha256:320b0ea7399f4b9af4741dcdddd7d40c05c36b0359679305d8a54df4e97065df";
          pullPolicy = "IfNotPresent";
        };
        securityContext.container.readOnlyRootFilesystem = false;
        service = {
          main = kubenix.lib.serviceIpFor "prowlarr" // {
            ports.main.port = 9696;
          };
          metrics = {
            enabled = true;
            type = "ClusterIP";
            ports = {
              metrics = {
                enabled = true;
                port = 9697;
              };
            };
          };
        };

        persistence = {
          config = {
            enabled = true;
            size = "1Gi";
            storageClass = "rook-ceph-block";
            targetSelector = {
              main = {
                main = { mountPath = "/config"; };
                exportarr = { mountPath = "/config"; readOnly = true; };
              };
            };
          };
          customDefinitions = {
            enabled = true;
            size = "1Gi";
            storageClass = "rook-ceph-block";
            targetSelector = {
              main = {
                main = { mountPath = "/config/Definitions/Custom"; };
                exportarr = { mountPath = "/config/Definitions/Custom"; readOnly = true; };
              };
            };
          };
          secretCustomIndexer = {
            enabled = true;
            type = "secret";
            objectName = "prowlarr-custom-definitions";
            expandObjectName = false;
            option = false;
            defaultMode = "0777";
            items = [
              { key = "custom-indexer"; path = "/config/Definitions/Custom/custom-indexer.yml"; }
            ];
          };
        };

        ingress = kubenix.lib.ingressDomainFor "prowlarr";

        metrics = {
          enabled = true;
          type = "servicemonitor";
          endpoints = [
            {
              port = "metrics";
              path = "/metrics";
            }
          ];
          targetSelector = "main";
          prometheusRule = {
            enabled = false;
          };
        };

        workload = {
          main = {
            podSpec = {
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
    };
  };
}

{ kubenix, homelab, ... }:

let
  app = "sftpgo";
  namespace = homelab.kubernetes.namespaces.applications;
  pvcName = "cephfs-shared-storage-root";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/sftpgo/helm-charts/sftpgo";
        chart = "sftpgo";
        version = "0.41.0";
        sha256 = "sha256-9RKsmCHmBQ0rkurHwksbP1ueIPtaMDNOO/WgZ7Z0ryg=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = {
          repository = "ghcr.io/drakkan/sftpgo";
          tag = "v2.7.0";
          pullPolicy = "IfNotPresent";
        };

        envFrom = [
          {
            secretRef = {
              name = "sftpgo-config";
            };
          }
        ];

        securityContext = {
          runAsUser = 2002;
          runAsGroup = 2002;
          readOnlyRootFilesystem = false;
        };

        podSecurityContext = {
          fsGroup = 2002;
          fsGroupChangePolicy = "OnRootMismatch";
        };

        config = {
          sftpd = {
            max_auth_tries = 4;
            bindings = [
              { port = 22; }
            ];
          };
          ftpd = {
            bindings = [
              {
                port = 21;
                tls_mode = 0;
                debug = true;
                active_connections_security = 1;
                passive_connections_security = 1;
                force_passive_ip = homelab.kubernetes.loadBalancer.services.sftpgo;
              }
            ];
            passive_port_range = {
              start = 50000;
              end = 50009;
            };
          };
        };

        sftpd.enabled = true;
        ftpd.enabled = true;
        webdavd.enabled = true;
        httpd.enabled = true;

        hostNetwork = false;

        service = {
          type = "LoadBalancer";
          externalTrafficPolicy = "Cluster";
          annotations = kubenix.lib.serviceAnnotationFor "sftpgo";
          ports.ftp.passiveRange.start = 50000;
          ports.ftp.passiveRange.end = 50009;
        };

        persistence = {
          enabled = true;
          pvc = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            storageClassName = "rook-ceph-block";
          };
        };

        volumes = [
          {
            name = "shared-storage";
            persistentVolumeClaim = {
              claimName = pvcName;
            };
          }
        ];

        volumeMounts = [
          {
            name = "shared-storage";
            mountPath = "/mnt/shared_storage";
            readOnly = false;
          }
        ];

        ui.ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          tls = [
            {
              secretName = "wildcard-tls";
              hosts = [ "sftpgo.${homelab.domain}" ];
            }
          ];
          hosts = [
            {
              host = "sftpgo.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
        };

        api.ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          tls = [
            {
              secretName = "wildcard-tls";
              hosts = [ "sftpgoapi.${homelab.domain}" ];
            }
          ];
          hosts = [
            {
              host = "sftpgoapi.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
        };
      };
    };
  };
}

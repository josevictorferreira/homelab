{ k8sLib, homelab, ... }:

let
  app = "sftpgo";
  namespace = homelab.kubernetes.namespaces.applications;
  pvcName = "cephfs-shared-storage-root";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch {
        chartUrl = "oci://ghcr.io/sftpgo/helm-charts/sftpgo";
        chart = "sftpgo";
        version = "0.40.0";
        sha256 = "sha256-BXSGD9IWdy7AVDSVo8a7HFitFutr2v96w2Nypp29blg=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = {
          repository = "ghcr.io/drakkan/sftpgo";
          tag = "v2.6.6-alpine@sha256:1dfde466cd2298c67050ea74798fd8e026f1667e657e0b8b2c68a7753ebe302a";
          pullPolicy = "IfNotPresent";
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
          annotations = k8sLib.serviceIpFor "sftpgo";
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
                { path = "/"; pathType = "Prefix"; }
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
                { path = "/"; pathType = "Prefix"; }
              ];
            }
          ];
        };
      };
    };
  };
}

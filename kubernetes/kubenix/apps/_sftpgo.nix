{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  domain = homelab.domain;
  dnsHosts = lib.mapAttrsToList (serviceName: ipAddress: "${homelab.kubernetes.loadBalancer.address} ${serviceName}.${domain}") homelab.kubernetes.loadBalancer.services;
  ipAddress = homelab.kubernetes.loadBalancer.services.sftpgo;
in
{
  kubernetes = {
    helm.releases."sftpgo" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://github.com/sftpgo/helm-chart";
          chart = "sftpgo";
          version = "0.38.0";
          sha256 = "sha256-nhvifpDdM8MoxF43cJAi6o+il2BbHX+udVAvvm1PukM=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = "apps";
      values = {
        image = {
          repository = "ghcr.io/drakkan/sftpgo";
          tag = "2025.07.0@sha256:da0216f6ee64c36dd9cae8576d3ec8c8f7436d6f5fb504a8f58bdda913647db5";
          pullPolicy = "IfNotPresent";
        };
        config = {
          sftpd = {
            max_auth_tries = 4;
            bindings = [ { port = 22; } ];
          };
          ftpd = {
            bindings = [
              {
                port = 21;
                tls_mode = 0;
                debug = true;
                active_connections_security = 1;
                force_passive_ip = ipAddress;
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
          annotations = {
            "metallb.universe.tf/allow-shared-ip" = "sftpgo";
          };
          loadBalancerIP = ipAddress;
          extraPorts = map (port: {
            name = "ftp-passive-${port}";
            port = port;
            targetPort = port;
            protocol = "TCP";
          }) (lib.lists.range 50000 50010);
        };

        persistence = {
          enabled = true;
          pvc = {};
        };

        volumes = [
          {
            name = "sftpgo-shared-storage";
            type = "pvc";
            readOnly = false;
          }
        ];

      };
    };
  };
}

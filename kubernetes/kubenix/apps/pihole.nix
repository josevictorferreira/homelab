{ lib, kubenix, homelab, ... }:

let
  domain = homelab.domain;
  dnsHosts = lib.mapAttrsToList (serviceName: ipAddress: "${homelab.kubernetes.loadBalancer.address} ${serviceName}.${domain}") homelab.kubernetes.loadBalancer.services;
in
{
  kubernetes = {
    helm.releases."pihole" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://mojo2600.github.io/pihole-kubernetes";
          chart = "pihole";
          version = "2.34.0";
          sha256 = "sha256-nhvifpDdM8MoxF43cJAi6o+il2BbHX+udVAvvm1PukM=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = "apps";
      values = {
        image = {
          repository = "pihole/pihole";
          tag = "2025.08.0@sha256:90a1412b3d3037d1c22131402bde19180d898255b584d685c84d943cf9c14821";
          pullPolicy = "IfNotPresent";
        };
        replicaCount = 3;
        DNS1 = builtins.elemAt homelab.dnsServers 0;
        DNS2 = builtins.elemAt homelab.dnsServers 1;
        podDnsConfig = {
          enabled = true;
          policy = "None";
          nameservers = [ "127.0.0.1" ] ++ homelab.dnsServers;
        };
        privileged = true;
        extraEnvVars = {
          "FTLCONF_dns_hosts" = lib.concatStringsSep "\n" dnsHosts;
          "TZ" = homelab.timeZone;
        };
        extraEnvVarsSecret = {
          "FTLCONF_webserver_api_password" = {
            name = "pihole-admin";
            key = "password";
          };
        };
        adlists = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt"
        ];
        serviceDns = kubenix.lib.plainServiceFor "pihole" // {
          mixedService = true;
        };
        serviceDhcp.enabled = false;
        admin = {
          enabled = true;
          existingSecret = "pihole-admin";
          passwordKey = "password";
        };
        persistentVolumeClaim = {
          enabled = true;
          storageClass = "rook-ceph-filesystem";
          size = "10Gi";
          accessModes = [ "ReadWriteMany" ];
        };
        ingress = {
          enabled = true;
          path = "/";
          pathType = "Prefix";
          ingressClassName = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          tls = [
            {
              hosts = [ "pihole.${domain}" ];
              secretName = "wildcard-tls";
            }
          ];
          hosts = [ "pihole.${domain}" ];
        };
        monitoring = {
          podMonitor.enabled = true;
          sidecar.enabled = true;
        };
      };
    };
  };
}

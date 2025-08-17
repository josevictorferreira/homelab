{ kubenix, lib, clusterConfig, clusterLib, ... }:

let
  dnsHosts = lib.mapAttrsToList (serviceName: ipAddress: "${clusterConfig.loadBalancer.address} ${serviceName}.${clusterConfig.domain}") clusterConfig.loadBalancer.services;
  dnsHostsStr = lib.concatStringsSep ";" dnsHosts;
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
          tag = "2025.07.0@sha256:da0216f6ee64c36dd9cae8576d3ec8c8f7436d6f5fb504a8f58bdda913647db5";
          pullPolicy = "IfNotPresent";
        };
        virtualHost = "pihole.${clusterConfig.domain}";
        replicaCount = 3;
        DNS1 = "1.1.1.1";
        DNS2 = "1.0.0.1";
        podDnsConfig = {
          enabled = true;
          policy = "None";
          nameservers = [ "127.0.0.1" ] ++ clusterConfig.dnsServers;
        };
        privileged = true;
        # ftl = {
        #   dns_listeningMode = "ALL";
        #   dns_hosts = dnsHostsStr;
        # };
        adlists = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt"
        ];
        serviceWeb = {
          type = "LoadBalancer";
          annotations = clusterLib.serviceIpFor "pihole";
        };
        serviceDns = {
          mixedService = true;
          type = "LoadBalancer";
          annotations = clusterLib.serviceIpFor "pihole";
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
              hosts = [ "pihole.${clusterConfig.domain}" ];
              secretName = "wildcard-tls";
            }
          ];
          hosts = [ "pihole.${clusterConfig.domain}" ];
        };
        monitoring = {
          podMonitor.enabled = false;
          sidecar.enabled = false;
        };
      };
    };
  };
}

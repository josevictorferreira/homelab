{ kubenix, lib, clusterConfig, ... }:

let
  dnsHosts = lib.mapAttrsToList (serviceName: ipAddress: "${ipAddress} ${serviceName}.${clusterConfig.domain}") clusterConfig.loadBalancer.services;
  dnsHostsStr = lib.concatStringsSep ";" dnsHosts;
in
{
  kubernetes = {
    helm.releases."pihole" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://mojo2600.github.io/pihole-kubernetes/";
          chart = "pihole";
          version = "2.34.0";
          sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
        };
      includeCRDs = true;
      noHooks = true;
      values = {
        image = {
          repository = "pihole/pihole";
          tag = "2025.07.0@sha256:da0216f6ee64c36dd9cae8576d3ec8c8f7436d6f5fb504a8f58bdda913647db5";
          pullPolicy = "IfNotPresent";
        };
        virtualHost = "pihole.local";
        replicaCount = 3;
        DNS1 = "1.1.1.1";
        DNS2 = "1.0.0.1";
        podDnsConfig = {
          enabled = true;
          policy = "None";
          nameservers = [ "127.0.0.1" ] ++ clusterConfig.dnsServers;
        };
        privileged = true;
        ftl = {
          dns_listeningMode = "ALL";
          dns_hosts = dnsHostsStr;
        };
        adlists = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt"
        ];
        serviceWeb = {
          type = "LoadBalancer";
          loadBalancerIP = clusterConfig.loadBalancer.services.pihole;
        };
        serviceDns = {
          mixedService = true;
          type = "LoadBalancer";
          loadBalancerIP = clusterConfig.loadBalancer.services.pihole;
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
          podMonitor.enabled = true;
          sidecar.enabled = true;
        };
      };
    };
  };
}

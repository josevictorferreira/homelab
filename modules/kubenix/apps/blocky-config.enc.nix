{ lib
, kubenix
, homelab
, ...
}:

let
  namespace = homelab.kubernetes.namespaces.applications;

  dnsHosts = lib.mapAttrsToList
    (
      serviceName: _ipAddress:
      "${kubenix.lib.domainFor serviceName} = ${homelab.kubernetes.loadBalancer.address}"
    )
    homelab.kubernetes.loadBalancer.services;

  # MagicDNS suffix for Tailscale - forward to unbound on subnet routers
  magicDnsSuffix = "tail96fefe.ts.net";

  blockyConfig = {
    upstreams = {
      groups = {
        default = homelab.dnsServers;
      };
      strategy = "parallel_best";
    };

    # Conditional forwarding for Tailscale MagicDNS zone
    # Forwards to unbound on alpha+beta (port 1053) which proxies to 100.100.100.100
    conditional = {
      fallbackUpstream = false;
      mapping = {
        "${magicDnsSuffix}" = "tcp+udp:10.10.10.200:1053,tcp+udp:10.10.10.201:1053";
      };
    };

    customDNS = {
      customTTL = "1h";
      filterUnmappedTypes = true;
      mapping = builtins.listToAttrs (
        map
          (
            entry:
            let
              parts = lib.splitString " = " entry;
            in
            {
              name = builtins.head parts;
              value = builtins.elemAt parts 1;
            }
          )
          dnsHosts
      );
    };

    blocking = {
      denylists = {
        ads = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt"
        ];
      };
      clientGroupsBlock = {
        default = [ "ads" ];
      };
      blockType = "zeroIp";
      blockTTL = "1m";
    };

    prometheus = {
      enable = true;
      path = "/metrics";
    };

    caching = {
      minTime = "5m";
      maxTime = "30m";
      prefetching = true;
    };

    log = {
      level = "info";
      format = "text";
      timestamp = true;
    };

    fqdnOnly.enable = true;

    redis = {
      address = "redis-headless";
      password = kubenix.lib.secretsFor "redis_password";
      database = 1;
      required = false;
    };
  };
  blockyConfigYaml = kubenix.lib.toYamlStr blockyConfig;
in
{
  kubernetes = {
    resources = {
      configMaps."blocky" = {
        metadata = {
          inherit namespace;
        };
        data."config.yml" = blockyConfigYaml;
      };
    };
  };
}

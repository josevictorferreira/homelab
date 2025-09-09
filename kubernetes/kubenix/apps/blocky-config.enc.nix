{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;

  dnsHosts = lib.mapAttrsToList
    (serviceName: ipAddress:
      "${kubenix.lib.domainFor serviceName} = ${homelab.kubernetes.loadBalancer.address}"
    )
    homelab.kubernetes.loadBalancer.services;

  blockyConfig = {
    upstreams = {
      groups = {
        default = homelab.dnsServers;
      };
      strategy = "parallel_best";
    };

    customDNS = {
      customTTL = "1h";
      filterUnmappedTypes = true;
      mapping = builtins.listToAttrs (map (entry:
        let parts = lib.splitString " = " entry;
        in { name = builtins.head parts; value = builtins.elemAt parts 1; }
      ) dnsHosts);
    };

    blocking = {
      denylists = {
        ads = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt"
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
in
{
  kubernetes = {
    resources = {
      configMaps."blocky-config" = {
        metadata = {
          name = "blocky-config";
          namespace = namespace;
        };
        data."config.yml" = kubenix.lib.toYamlStr blockyConfig;
      };
    };
  };
}

{ lib, config, hostName, homelab, ... }:

let
  cfg = config.roles.nixosServer;
  clusterConfig = homelab.cluster;
  commonsPath = homelab.paths.commons;
in

{
  options.roles.nixosServer = {
    enable = lib.mkEnableOption "Enable default nix machine configurations";
  };

  imports = [
    "${commonsPath}/nix.nix"
    "${commonsPath}/locale.nix"
    "${commonsPath}/static-ip.nix"
  ];

  config = lib.mkIf cfg.enable {
    nixDefaults.enable = true;
    locale = {
      timeZone = clusterConfig.timeZone;
      enable = true;
    };
    networking.firewall.enable = false;

    networking.hostName = hostName;
    networking.domain = clusterConfig.domain;
    networking.fqdn = "${hostName}.${clusterConfig.domain}";
    networking.hostId = lib.mkDefault
      (builtins.substring 0 8 (builtins.hashString "sha1" hostName));

    networking.staticIP = {
      enable = true;
      interface = clusterConfig.hosts.${hostName}.interface;
      address = clusterConfig.hosts.${hostName}.ipAddress;
      prefixLength = 24;
      gateway = clusterConfig.gateway;
      nameservers = clusterConfig.dnsServers;
    };

    services.earlyoom.enable = true;

    boot.supportedFilesystems = [ "nfs" ];
    services.rpcbind.enable = true;

    zramSwap = {
      enable = true;
      memoryPercent = 30;
      algorithm = "zstd";
    };

    boot.kernel.sysctl."vm.swappiness" = 180;
  };
}

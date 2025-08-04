{ lib, config, hostName, clusterConfig, commonsPath, ... }:

let
  cfg = config.roles.nixosServer;
in

{
  options.roles.nixosServer = {
    enable = lib.mkEnableOption "Enable default nix machine configurations";
  };

  config = lib.mkIf cfg.enable {
    imports = [
      "${commonsPath}/nix.nix"
      "${commonsPath}/locale.nix"
      "${commonsPath}/static-ip.nix"
    ];

    nix.enable = true;
    locale.enable = true;
    networking.firewall.enable = false;

    networking.hostName = hostName;
    networking.domain = clusterConfig.clusterDomain;
    networking.fqdn = "${hostName}.${clusterConfig.clusterDomain}";
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

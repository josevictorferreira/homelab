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
    networking.staticIP = {
      enable = true;
      interface = clusterConfig.hosts.${hostName}.interface;
      address = clusterConfig.hosts.${hostName}.ipAddress;
      prefixLength = 24;
      gateway = clusterConfig.gateway;
      nameservers = clusterConfig.dnsServers;
    };
  };
}

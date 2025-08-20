{ lib, config, hostName, homelab, ... }:

let
  cfg = config.profiles."nixos-server";
in

{
  options.profiles."nixos-server" = {
    enable = lib.mkEnableOption "Enable default nix machine configurations";
  };

  imports = [
    "${homelab.paths.commons}/nix.nix"
    "${homelab.paths.commons}/locale.nix"
    "${homelab.paths.commons}/static-ip.nix"
  ];

  config = lib.mkIf cfg.enable {
    nixDefaults.enable = true;
    locale = {
      timeZone = homelab.timeZone;
      enable = true;
    };
    networking.firewall.enable = false;

    networking.hostName = hostName;
    networking.domain = homelab.domain;
    networking.fqdn = "${hostName}.${homelab.domain}";
    networking.hostId = lib.mkDefault
      (builtins.substring 0 8 (builtins.hashString "sha1" hostName));

    networking.staticIP = {
      enable = true;
      interface = homelab.nodes.hosts.${hostName}.interface;
      address = homelab.nodes.hosts.${hostName}.ipAddress;
      prefixLength = 24;
      gateway = homelab.gateway;
      nameservers = [ homelab.kubernetes.loadBalancer.services.pihole ] ++ homelab.dnsServers;
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

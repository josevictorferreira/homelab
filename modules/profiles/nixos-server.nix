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
      inherit (homelab) timeZone;
      enable = true;
    };
    networking = {
      firewall.enable = false;
      inherit hostName;
      inherit (homelab) domain;
      fqdn = "${hostName}.${homelab.domain}";
      hostId = lib.mkDefault
        (builtins.substring 0 8 (builtins.hashString "sha1" hostName));

      staticIP = {
        enable = true;
        inherit (homelab.nodes.hosts.${hostName}) interface;
        address = homelab.nodes.hosts.${hostName}.ipAddress;
        prefixLength = 24;
        inherit (homelab) gateway;
        nameservers = [ homelab.kubernetes.loadBalancer.services.blocky ] ++ homelab.dnsServers;
      };
    };

    services = {
      earlyoom.enable = true;

      journald.extraConfig = ''
        SystemMaxUse=100M
        SystemMaxFileSize=50M
        MaxRetentionSec=7day
      '';

      rpcbind.enable = true;
    };

    zramSwap = {
      enable = true;
      memoryPercent = 30;
      algorithm = "zstd";
    };

    boot.kernel.sysctl."vm.swappiness" = 180;

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };
}

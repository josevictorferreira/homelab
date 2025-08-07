{ lib, pkgs, config, clusterConfig, usersConfig, flakeRoot, ... }:

let
  cfg = config.k8sNodeDefaults;
  username = config.users.users.${usersConfig.admin.username}.name;
in
{
  options.k8sNodeDefaults = {
    enable = lib.mkEnableOption "Enable base configurations for k3s nodes";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.k3s_token = {
      owner = username;
      mode = "0400";
    };

    environment.systemPackages = with pkgs; [
      cilium-cli
      fluxcd
    ];

    boot.kernelModules = [
      "ip6_tables"
      "ip6table_mangle"
      "ip6table_raw"
      "ip6table_filter"
    ];

    networking.enableIPv6 = true;
    networking.nat = {
      enable = true;
      enableIPv6 = true;
    };

    networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
    networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;
  };
}

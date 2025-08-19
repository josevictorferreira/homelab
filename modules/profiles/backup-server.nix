{ lib, config, pkgs, hostName, ... }:

let
  cfg = config.profiles."backup-server";
  servicesPath = homelab.paths.services;
  wolMachines = lib.attrsets.filterAttrs (name: _: name != hostName) homelab.cluster.clusterConfig.hosts;
  wolMachinesList = lib.attrValues
    (lib.mapAttrs (name: value: value // { inherit name; })
      wolMachines);
in
{
  options.profiles."backup-server" = {
    enable = lib.mkEnableOption "Enable backup target role";
  };

  imports = [
    "${servicesPath}/wake-on-lan-observer.nix"
    "${servicesPath}/minio.nix"
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      zfs
    ];

    boot.supportedFilesystems = [ "zfs" ];

    boot.zfs.extraPools = [ "backup-pool" ];

    services.nfs.server = {
      enable = true;
      exports = ''
        /backups *(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    services.minioCustom = {
      enable = true;
      dataDir = "/backups/minio";
      rootCredentialsFile = "/run/secrets/minio_credentials";
    };

    services.wakeOnLanObserver = {
      enable = true;
      machines = wolMachinesList;
    };

    networking.firewall.allowedTCPPorts = [ 2049 111 ];
    networking.firewall.allowedUDPPorts = [ 2049 111 ];

    systemd.tmpfiles.rules = [
      "d /backups 0755 root root -"
    ];
  };
}

{ pkgs, ... }:

{
  imports = [
    ./../services/wake-on-lan-observer.nix
    ./../services/minio.nix
  ];

  environment.systemPackages = with pkgs; [
    btrfs-progs
    zfs
  ];

  boot.initrd.kernelModules = [ "zfs" ];

  boot.supportedFilesystems = [ "btrfs" "zfs" ];

  boot.zfs.extraPools = [ "backup-pool" ];

  services.nfs.server = {
    enable = true;
    exports = ''
      /backups *(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  networking.firewall.allowedTCPPorts = [ 2049 111 ];
  networking.firewall.allowedUDPPorts = [ 2049 111 ];

  systemd.tmpfiles.rules = [
    "d /backups 0755 root root -"
  ];
}

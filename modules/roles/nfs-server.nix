{ ... }:

{
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/backup-storage/longhorn *(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # Open firewall for NFS
  networking.firewall.allowedTCPPorts = [ 2049 111 ];
  networking.firewall.allowedUDPPorts = [ 2049 111 ];

  # Create backup directory
  systemd.tmpfiles.rules = [
    "d /mnt/backup-storage/longhorn 0755 root root -"
  ];
}

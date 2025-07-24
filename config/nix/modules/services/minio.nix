{ ... }:

{
  services.minio = {
    enable = true;
    dataDir = [ "/mnt/backup-storage/minio" ];
    listenAddress = "0.0.0.0:9000";
    consoleAddress = "0.0.0.0:9001";
    rootPasswordFile = "/etc/minio-root-password";
  };

  networking.firewall.allowedTCPPorts = [ 9000 9001 ];

  systemd.tmpfiles.rules = [
    "d /mnt/backup-storage/minio 0755 minio-user minio-user -"
  ];
}

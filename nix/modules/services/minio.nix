{ config, ... }:

let
  minioCredentialsFile = config.sops.templates."minio-env".path;
in
{
  services.minio = {
    enable = true;
    dataDir = [ "/backup/minio" ];
    rootCredentialsFile = minioCredentialsFile;
    listenAddress = "0.0.0.0:9000";
    consoleAddress = "0.0.0.0:9001";
    region = "sa-east-1";
  };

  systemd.tmpfiles.rules = [
    "d /backup/minio 0750 minio minio -"
  ];

  networking.firewall.allowedTCPPorts = [ 9000 9001 ];
}

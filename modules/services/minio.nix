{ lib, config, ... }:

let
  cfg = config.services.minioCustom;
in
{
  options.services.minioCustom = {
    enable = lib.mkEnableOption "Enable MinIO object storage service";
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/backup/minio";
      description = "Directories where MinIO will store its data.";
    };
    rootCredentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/minio_credentials";
      description = "File containing the root credentials for MinIO.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.minio = {
      enable = true;
      dataDir = [ cfg.dataDir ];
      rootCredentialsFile = cfg.rootCredentialsFile;
      listenAddress = "0.0.0.0:9000";
      consoleAddress = "0.0.0.0:9001";
      region = "sa-east-1";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 minio minio -"
    ];

  };
}

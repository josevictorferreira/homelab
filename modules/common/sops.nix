{ lib, config, ... }:

let
  cfg = config.sops;
  secretsPath = config.homelab.project.paths.secrets;
  defaultAgeKeyFile = ".config/sops/age/keys.txt";
in
{
  options.sops = {
    enable = lib.mkEnableOption "Enable SOPS for secret management";
    username = lib.mkOption {
      type = lib.types.str;
      default = "linuxuser";
      description = "The username for the user managing secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = "${secretsPath}/hosts-secrets.enc.yaml";
      age.keyFile = "${config.users.users.${cfg.username}.home}/${defaultAgeKeyFile}";
    };

    sops.secrets."minio_credentials" = {
      owner = config.users.users.${cfg.username}.name;
      mode = "0400";
    };

    environment.variables.SOPS_AGE_KEY_FILE = "${config.users.users.${cfg.username}.home}/${defaultAgeKeyFile}";
  };
}

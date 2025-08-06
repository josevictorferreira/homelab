{ lib, pkgs, config, ... }:

let
  cfg = config.users;
in
{
  options.users = {
    enable = lib.mkEnableOption "Enable user management";
    username = lib.mkOption {
      type = lib.types.str;
      default = "linuxuser";
      description = "The username for the normal user.";
    };
    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys for the user.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      home = "/home/${cfg.username}";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = cfg.keys;
    };

    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };

    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };
}

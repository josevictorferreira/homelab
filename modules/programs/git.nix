{ lib, config, ... }:

let
  cfg = config.programs.gitCustom;
in
{
  options.programs.gitCustom = {
    enable = lib.mkEnableOption "Admin tools for the cluster admin user";
    name = lib.mkOption {
      type = lib.types.str;
      default = "John Doe";
      description = "The name of the cluster admin user.";
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "john@doe.com";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      config = {
        user.name = cfg.name;
        user.email = cfg.email;
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        push.followTags = true;
        pull.rebase = true;
        fetch = {
          prune = true;
          tags = true;
        };
      };
    };
  };
}

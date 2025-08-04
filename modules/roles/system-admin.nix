{ lib, config, clusterAdmin, commonsPath, programsPath, ... }:

let
  cfg = config.roles.systemAdmin;
in
{
  options.roles.systemAdmin = {
    enable = lib.mkEnableOption "Admin tools for the cluster admin user";
  };

  config = lib.mkIf cfg.enable {
    imports = [
      "${commonsPath}/users.nix"
      "${commonsPath}/ssh.nix"
      "${commonsPath}/sops.nix"
      "${programsPath}/vim.nix"
      "${programsPath}/zsh.nix"
      "${programsPath}/git.nix"
    ];

    users = {
      enable = true;
      username = clusterAdmin.username;
      keys = clusterAdmin.keys;
    };

    sops = {
      enable = true;
      username = clusterAdmin.username;
    };

    programs.vim.enable = true;
    programs.zsh.enable = true;
    programs.git = {
      enable = true;
      name = clusterAdmin.name;
      email = clusterAdmin.email;
    };

    services.ssh.enable = true;
  };
}

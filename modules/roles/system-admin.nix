{ lib, config, pkgs, usersConfig, commonsPath, programsPath, ... }:

let
  cfg = config.roles.systemAdmin;
in
{
  options.roles.systemAdmin = {
    enable = lib.mkEnableOption "Admin tools for the cluster admin user";
  };

  imports = [
    "${commonsPath}/users.nix"
    "${commonsPath}/ssh.nix"
    "${commonsPath}/sops.nix"
    "${programsPath}/vim.nix"
    "${programsPath}/zsh.nix"
    "${programsPath}/git.nix"
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      age
      sops
      git
      vim
      curl
      gnumake
      htop
    ];

    users = {
      enable = true;
      username = usersConfig.admin.username;
      keys = usersConfig.admin.keys;
    };

    sops = {
      enable = true;
      username = usersConfig.admin.username;
    };

    programs.vim.enable = true;
    programs.zsh.enable = true;
    programs.git = {
      enable = true;
      name = usersConfig.admin.name;
      email = usersConfig.admin.email;
    };

    services.ssh.enable = true;
  };
}

{ lib, config, pkgs, homelab, ... }:

let
  cfg = config.profiles."system-admin";
  usersConfig = homelab.users;
  commonsPath = homelab.paths.commons;
  programsPath = homelab.paths.programs;
in
{
  options.profiles."system-admin" = {
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
      ncdu
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

    programs.vimCustom.enable = true;
    programs.zshCustom.enable = true;
    programs.gitCustom = {
      enable = true;
      name = usersConfig.admin.name;
      email = usersConfig.admin.email;
    };

    services.ssh.enable = true;
  };
}

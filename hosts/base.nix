{ pkgs, hostName, hostConfig, ... }:

let
  roles = map (role: ./../modules/roles/${role}.nix) hostConfig.roles;
in
{
  imports = [
    ./../modules/common/sops.nix
    ./../modules/common/nix.nix
    ./../modules/common/locale.nix
    ./../modules/common/ssh.nix
    ./../modules/common/static-ip.nix
    ./../modules/common/users.nix
    ./../modules/programs/vim.nix
    ./../modules/programs/git.nix
    ./../modules/programs/zsh.nix
  ] ++ roles;

  environment.systemPackages = with pkgs; [
    age
    sops
    git
    vim
    wget
    curl
    gnumake
    htop
  ];

  environment.sessionVariables = {
    HOSTNAME = hostName;
  };

  networking.hostName = hostName;
  networking.staticIP = {
    enable = true;
    interface = hostConfig.interface;
    address = hostConfig.ipAddress;
  };
}

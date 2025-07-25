{ pkgs, hostName, ... }:

{
  imports = [
    ./../modules/common/sops.nix
    ./../modules/common/nix.nix
    ./../modules/programs/vim.nix
    ./../modules/programs/git.nix
    ./../modules/programs/zsh.nix
  ];

  environment.systemPackages = with pkgs; [
    sops
    age
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
}

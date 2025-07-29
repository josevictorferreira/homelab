{ pkgs, hostName, hostConfig, clusterConfig, ... }:

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

  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

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

  boot.kernel.sysctl."kernel.hostname" = "${hostName}.${clusterConfig.clusterDomain}";
  networking.hostName = hostName;
  networking.domain = clusterConfig.clusterDomain;
  networking.fqdn = "${hostName}.${clusterConfig.clusterDomain}";
  networking.staticIP = {
    enable = true;
    interface = hostConfig.interface;
    address = hostConfig.ipAddress;
  };
}

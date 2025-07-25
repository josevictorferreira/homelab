{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb.layout = "us";

  networking.hostName = "base";
  networking.useDHCP = true;

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    sops
    age
    git
    vim
    curl
    gnumake
    htop
  ];

  # make a copy of current system configuration to /run/current-system/configuration.nix in case of a accidental deletion
  system.copySystemConfiguration = true;

  services.qemuGuest.enable = true;
  services.openssh.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    enableLsColors = true;

    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      l = "ls -l";
      gs = "git status";
      gcmsg = "git commit -m ";
      gp = "git push";
      gl = "git pull";
      gpr = "git pull --rebase";
    };
    histSize = 10000;
  };

  system.stateVersion = "25.05";

  nix.settings.trusted-users = [ "root" "@wheel" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}

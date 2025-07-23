{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "k8s-nixos-template";
  networking.interfaces.ens18 = {
    ipv4.addresses = [{
      address = "10.10.10.250";
      prefixLength = 24;
    }];
    useDHCP = false;
  };
  networking.useDHCP = false;
  networking.defaultGateway = {
    address = "10.10.10.1";
    interface = "ens18";
  };
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.josevictor = {
    isNormalUser = true;
    home = "/home/josevictor";
    description = "Jose Victor Ferreira";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPAXdWHFx9UwUOXlapiVD0mzM0KL9VsMlblMAc46D9PV josevictor@josevictor-nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVNsxVT6rzeyqZVlJVdQgKEzK2z0fOFNRZMAvQvBxbX josevictorferreira@macos-macbook"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    gnumake
    htop
  ];

  # make a copy of current system configuration to /run/current-system/configuration.nix in case of a accidental deletion
  system.copySystemConfiguration = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.xserver.xkb.layout = "us";
  services.qemuGuest.enable = true;

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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}

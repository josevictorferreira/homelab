{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "zfs" ];
    kernel.sysctl."vm.swappiness" = 180;
  };

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  services = {
    xserver.xkb.layout = "us";
    openssh.enable = true;
    earlyoom.enable = true;
  };

  users.users.josevictor = {
    isNormalUser = true;
    home = "/home/josevictor";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPAXdWHFx9UwUOXlapiVD0mzM0KL9VsMlblMAc46D9PV josevictor@josevictor-nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVNsxVT6rzeyqZVlJVdQgKEzK2z0fOFNRZMAvQvBxbX josevictorferreira@macos-macbook"
    ];
  };

  networking = {
    firewall.enable = false;
    hostName = "lab-alpha-cp";
    hostId = builtins.substring 0 8 (builtins.hashString "sha1" "lab-alpha-cp");
    useDHCP = false;

    interfaces.enp1s0 = {
      mtu = 1500;
      ipv4.addresses = [{
        address = "10.10.10.200";
        prefixLength = 24;
      }];
    };

    defaultGateway = {
      address = "10.10.10.1";
      interface = "enp1s0";
    };
  };

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

  zramSwap = {
    enable = true;
    memoryPercent = 30;
    algorithm = "zstd";
  };

  system.copySystemConfiguration = true;

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

  nix.settings = {
    trusted-users = [ "root" "@wheel" ];
    experimental-features = [ "nix-command" "flakes" ];
  };
}

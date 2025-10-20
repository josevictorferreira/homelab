{ pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking.hostName = "homelab-recovery";
  time.timeZone = "America/Sao_Paulo";

  networking.networkmanager.enable = false;

  networking.useDHCP = false;
  networking.interfaces.enp1s0 = {
    mtu = 1500;
    ipv4.addresses = [
      {
        address = "10.10.10.240";
        prefixLength = 24;
      }
    ];
    useDHCP = false;
  };
  networking.defaultGateway = {
    address = "10.10.10.1";
    interface = "enp1s0";
  };
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    openFirewall = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPAXdWHFx9UwUOXlapiVD0mzM0KL9VsMlblMAc46D9PV josevictor@josevictor-nixos"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVNsxVT6rzeyqZVlJVdQgKEzK2z0fOFNRZMAvQvBxbX josevictorferreira@macos-macbook"
  ];

  users.users.rescue = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPAXdWHFx9UwUOXlapiVD0mzM0KL9VsMlblMAc46D9PV josevictor@josevictor-nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVNsxVT6rzeyqZVlJVdQgKEzK2z0fOFNRZMAvQvBxbX josevictorferreira@macos-macbook"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  boot.supportedFilesystems = [ "zfs" ];
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    jq
    ripgrep
    fd
    htop
    btop
    parted
    gptfdisk
    util-linux
    lvm2
    mdadm
    e2fsprogs
    btrfs-progs
    cryptsetup
    zfs
    nfs-utils
    iproute2
    iputils
    ethtool
    nmap
    tcpdump
    socat
    smartmontools
    restic
    rclone
    sops
    age
  ];

  isoImage.appendToMenuLabel = " (Homelab Rescue)";

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];
}

{ pkgs, ... }:

{
  imports = [
    "${pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.hostName = "homelab-recovery";
  time.timeZone = "America/Sao_Paulo";

  networking.networkmanager.enable = false;

  networking.useDHCP = false;
  networking.dhcpcd.enable = true;
  networking.dhcpcd.extraConfig = ''
    interface en*
    interface eth*

    static ip_address=10.10.10.240/24
    static routers=10.10.10.1
    static domain_name_servers=10.10.10.1 1.1.1.1 9.9.9.9
  '';

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UseDNS = false;
    };
    openFirewall = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
  ];

  users.users.rescue = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
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
    smbclient
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
    kubectl
    helm
    k9s
  ];

  isoImage.appendToMenuLabel = " (Homelab Rescue)";
}

{ lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  environment.systemPackages = with pkgs; [
    btrfs-progs
  ];

  boot.supportedFilesystems = [ "btrfs" ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
      fsType = "ext4";
    };

  fileSystems."/mnt/backup-storage" = {
    device = "/dev/disk/by-uuid/0a86fe93-c3c7-4e6d-acef-54dca7fdb4a6";
    fsType = "btrfs";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "compress=zstd"
      "ssd"
    ];
  };
  fileSystems."/mnt/shared_storage_1" = {
    device = "10.10.10.200:/mnt/shared_storage_1";
    fsType = "nfs";
    options = [ "rw" "soft" "noatime" "actimeo=60" "vers=3" "x-systemd.automount" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

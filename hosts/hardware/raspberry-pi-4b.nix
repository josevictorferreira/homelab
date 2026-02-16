{ lib, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
  boot.kernelModules = [ "usb_storage" ];
  boot.extraModulePackages = [ ];

  # SanDisk Extreme Pro (0781:55af) + Pi 4B VL805 USB controller workarounds:
  # - Blacklist UAS driver (crashes with SCSI INQUIRY timeouts)
  # - Force usb-storage quirk "u" flag (ignore UAS, use BOT protocol) so
  #   the builtin usb-storage driver auto-binds at boot
  boot.blacklistedKernelModules = [ "uas" ];
  boot.kernelParams = [ "usb-storage.quirks=0781:55af:u" ];
  boot.modprobeConfig.enable = true;

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
      fsType = "ext4";
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

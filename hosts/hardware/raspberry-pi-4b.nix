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

  # Blacklist UAS driver — SanDisk USB drives crash with UAS on Pi 4B's VL805 controller.
  # Forces fallback to usb-storage (BOT protocol) which is stable.
  boot.blacklistedKernelModules = [ "uas" ];
  boot.modprobeConfig.enable = true;

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
      fsType = "ext4";
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

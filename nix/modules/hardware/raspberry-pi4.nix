{ lib, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
      fsType = "ext4";
    };
  fileSystems."/mnt/shared_storage_1" = {
    device = "10.10.10.200:/mnt/shared_storage_1";
    fsType = "nfs";
    options = [ "rw" "soft" "noatime" "actimeo=60" "vers=3" "x-systemd.automount" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

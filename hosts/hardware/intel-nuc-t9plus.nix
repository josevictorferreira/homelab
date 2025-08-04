{ config, lib, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "rpool/root";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    {
      device = "rpool/nix";
      fsType = "zfs";
    };

  fileSystems."/var/log" =
    {
      device = "rpool/log";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      #device = "/dev/disk/by-uuid/2E6D-F4D0";
      device = "/dev/disk/by-partlabel/EFI";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

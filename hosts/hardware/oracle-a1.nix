{ lib, inputs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.disko.nixosModules.disko
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "xhci_pci"
    ];
  };

  # Cloud node: DHCP-managed VNIC, and unlike LAN nodes the NixOS firewall
  # stays on as defense in depth behind the OCI security list. The tailscale
  # profile opens its own UDP port and trusts tailscale0.
  networking = {
    useDHCP = lib.mkDefault true;
    firewall.enable = lib.mkForce true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

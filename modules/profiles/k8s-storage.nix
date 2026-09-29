{ lib, config, pkgs, ... }:

let
  cfg = config.profiles."k8s-storage";
in
{
  options.profiles."k8s-storage" = {
    enable = lib.mkEnableOption "Enable the node to be a Kubernetes storage node";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ceph
      ceph-client
      util-linux
      parted
      gptfdisk
      lvm2
    ];

    boot.kernelModules = [
      "ceph"
      "rbd"
      "nfs"
    ];

    # Blacklist nbd module to prevent ceph-volume from hanging when scanning devices
    # nbd devices cause ceph-bluestore-tool show-label to hang indefinitely
    boot.blacklistedKernelModules = [ "nbd" ];

    # ceph-volume chowns OSD partitions to ceph (167) only at activation. Any
    # later udev "change" event (e.g. a partition-table re-read) recreates the
    # node as root:disk and the OSD fails its next restart with
    # "open got: (13) Permission denied". Keep ownership in udev itself.
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_PART_ENTRY_NAME}=="CEPH_OSD_*", OWNER="167", GROUP="167", MODE="0660"
    '';

    systemd.services.containerd.serviceConfig = {
      LimitNOFILE = lib.mkForce null;
    };
  };
}

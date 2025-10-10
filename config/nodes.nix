{ lib, ... }:

let
  filterByRoles =
    hosts: role: (lib.attrsets.filterAttrs (name: value: builtins.elem role value.roles) hosts);
in
rec {
  hosts = {
    # lab-pi-bk = {
    #   ipAddress = "10.10.10.209";
    #   system = "aarch64-linux";
    #   machine = "raspberry-pi-4b";
    #   interface = "end0";
    #   mac = "DC:A6:32:BD:01:4C";
    #   roles = [
    #     "nixos-server"
    #     "system-admin"
    #     "backup-server"
    #   ];
    # };
    lab-alpha-cp = {
      ipAddress = "10.10.10.200";
      system = "x86_64-linux";
      machine = "intel-nuc-gk3v";
      interface = "enp1s0";
      mac = "68:1D:EF:30:C1:03";
      disks = [
        "/dev/disk/by-partlabel/CEPH_OSD_NVME"
        "/dev/disk/by-partlabel/CEPH_OSD_SATA"
      ];
      roles = [
        "nixos-server"
        "system-admin"
        "k8s-server"
        "k8s-storage"
        "k8s-control-plane"
      ];
    };
    lab-beta-cp = {
      ipAddress = "10.10.10.201";
      system = "x86_64-linux";
      machine = "intel-nuc-t9plus";
      interface = "enp1s0";
      mac = "68:1D:EF:3B:71:4E";
      disks = [
        "/dev/disk/by-partlabel/CEPH_OSD_NVME"
      ];
      roles = [
        "nixos-server"
        "system-admin"
        "k8s-server"
        "k8s-storage"
        "k8s-control-plane"
      ];
    };
    lab-gamma-wk = {
      ipAddress = "10.10.10.202";
      system = "x86_64-linux";
      machine = "intel-nuc-gk3v";
      interface = "enp1s0";
      mac = "68:1D:EF:3E:30:37";
      disks = [
        "/dev/disk/by-partlabel/CEPH_OSD_SATA"
      ];
      roles = [
        "nixos-server"
        "system-admin"
        "k8s-server"
        "k8s-storage"
        "k8s-worker"
      ];
    };
    lab-delta-cp = {
      ipAddress = "10.10.10.203";
      system = "x86_64-linux";
      machine = "amd-ryzen-beelink-eqr5";
      interface = "enp1s0";
      mac = "B0:41:6F:16:1F:72";
      disks = [
        "/dev/disk/by-partlabel/CEPH_OSD_NVME"
      ];
      roles = [
        "nixos-server"
        "system-admin"
        "k8s-server"
        "k8s-storage"
        "k8s-control-plane"
        "amd-gpu"
      ];
    };
  };

  groups = [
    "k8s-control-plane"
    "k8s-worker"
    "k8s-server"
    "k8s-storage"
    "backup-server"
    "nixos-server"
    "amd-gpu"
  ];

  group = lib.listToAttrs (
    map (role: {
      name = role;
      value = rec {
        configs = filterByRoles hosts role;
        names = lib.attrNames configs;
      };
    }) groups
  );
}

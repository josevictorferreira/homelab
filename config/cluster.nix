{ lib }:

let
  filterHostsWithRoles = hosts: role: (lib.attrsets.filterAttrs (name: value: builtins.elem role value.roles) hosts);
in
rec {
  name = "ze-homelab";

  domain = "josevictor.me";

  timeZone = "America/Sao_Paulo";

  ipAddress = "10.10.10.250";

  gateway = "10.10.10.1";

  dnsServers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  hosts = {
    lab-pi-bk = {
      ipAddress = "10.10.10.209";
      system = "aarch64-linux";
      machine = "raspberry-pi-4b";
      interface = "end0";
      mac = "DC:A6:32:BD:01:4C";
      roles = [
        "nixos-server"
        "system-admin"
        "backup-server"
      ];
    };
    lab-alpha-cp = {
      ipAddress = "10.10.10.200";
      system = "x86_64-linux";
      machine = "intel-nuc-gk3v";
      interface = "enp1s0";
      mac = "68:1D:EF:30:C1:03";
      storageDevices = [
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
      roles = [
        "nixos-server"
        "system-admin"
        "k8s-server"
        "k8s-storage"
        "k8s-control-plane"
      ];
    };
  };

  nodeGroup = {
    k8sControlPlanes = filterHostsWithRoles hosts "k8s-control-plane";
    k8sWorkers = filterHostsWithRoles hosts "k8s-worker";
    k8sServers = filterHostsWithRoles hosts "k8s-server";
    k8sStorages = filterHostsWithRoles hosts "k8s-storage";
    backupServers = filterHostsWithRoles hosts "backup-server";
    nixosServers = filterHostsWithRoles hosts "nixos-server";
  };

  nodeGroupHostNames = {
    k8sControlPlanes = builtins.attrNames nodeGroup.k8sControlPlanes;
    k8sWorkers = builtins.attrNames nodeGroup.k8sWorkers;
    k8sServers = builtins.attrNames nodeGroup.k8sServers;
    k8sStorages = builtins.attrNames nodeGroup.k8sStorages;
    backupServers = builtins.attrNames nodeGroup.backupServers;
    nixosServers = builtins.attrNames nodeGroup.nixosServers;
  };

  loadBalancer = {
    address = "10.10.10.100";
    range = {
      start = "10.10.10.100";
      stop = "10.10.10.199";
    };
    services = {
      linkwarden = "10.10.10.103";
      glance = "10.10.10.127";
      libebooker = "10.10.10.123";
    };
  };

  portsUdpToExpose = [
    8472
    51820
    51821
  ];

  portsTcpToExpose = [
    443
    2379
    2380
    4240 # Cilium health
    6443
    6444
    8472
    10250
  ];
}

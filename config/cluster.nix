{ lib }:

let
  filterHostsWithRoles = hosts: role: (lib.attrsets.filterAttrs (name: value: builtins.elem role value.roles) hosts);
  filterHostsNamesWithRoles = hosts: role: (builtins.attrNames (filterHostsWithRoles hosts role));
in
rec {
  name = "ze-homelab";

  domain = "ze.lab";

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
      roles = [
        "nixos-server"
        "system-admin"
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
        "k8s-control-plane"
      ];
    };
  };

  nodeGroups = rec {
    k8sControlPlanes = filterHostsNamesWithRoles hosts "k8s-control-plane";
    k8sWorkers = filterHostsNamesWithRoles hosts "k8s-worker";
    k8sServers = k8sControlPlanes ++ k8sWorkers;
    backupServers = filterHostsNamesWithRoles hosts "backup-server";
    nixosServers = filterHostsNamesWithRoles hosts "nixos-server";
  };

  tokenFile = "/run/secrets/k3s_token";

  portsUdpToExpose = [
    8472
    51820
    51821
  ];

  portsTcpToExpose = [
    2379
    2380
    6443
    6444
    10250
  ];
}

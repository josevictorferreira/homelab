{
  clusterName = "homelab";

  clusterIpAddress = "10.10.10.250";

  hosts = {
    raspberry-pi4 = {
      ipAddress = "10.10.10.209";
      system = "aarch64-linux";
      machine = "raspberry-pi4";
      interface = "end0";
      roles = [ "backup-server" ];
    };
    k8s-node-210-alpha = {
      ipAddress = "10.10.10.210";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-211-beta = {
      ipAddress = "10.10.10.211";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-212-gamma = {
      ipAddress = "10.10.10.212";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-master" ];
    };
    k8s-node-213-delta = {
      ipAddress = "10.10.10.213";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-214-epsilon = {
      ipAddress = "10.10.10.214";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-215-zeta = {
      ipAddress = "10.10.10.215";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-master" ];
    };
    k8s-node-216-eta = {
      ipAddress = "10.10.10.216";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-217-theta = {
      ipAddress = "10.10.10.217";
      system = "x86_64-linux";
      machine = "intel-nuc-vm";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-218-iota = {
      ipAddress = "10.10.10.218";
      system = "x86_64-linux";
      machine = "amd-mini-pc";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-219-kappa = {
      ipAddress = "10.10.10.219";
      system = "x86_64-linux";
      machine = "amd-mini-pc";
      interface = "ens18";
      roles = [ "k8s-master" ];
    };
    k8s-node-220-lambda = {
      ipAddress = "10.10.10.220";
      system = "x86_64-linux";
      machine = "amd-mini-pc";
      interface = "ens18";
      roles = [ "k8s-worker" ];
    };
    k8s-node-template = {
      ipAddress = "10.10.10.250";
      system = "x86_64-linux";
      machine = "amd-mini-pc";
      interface = "ens18";
      roles = [ "vm-template" ];
    };
  };

  masters = [
    "k8s-node-219-kappa"
    "k8s-node-212-gamma"
    "k8s-node-215-zeta"
  ];

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

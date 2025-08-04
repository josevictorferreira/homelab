{ lib, config, hostName, clusterConfig, ... }:

let
  cfg = config.roles.k8sControlPlane;
  clusterInitFlags = [
    "--cluster-init"
  ];
in
{
  options.roles.k8sControlPlane = {
    enable = lib.mkEnableOption "Enable Kubernetes control plane role";
    isInit = lib.mkOption {
      type = lib.types.bool;
      default = (builtins.head clusterConfig.controlPlanes) == hostName;
      description = "Whether this node is the initial control plane node";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
    networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;

    services.k3s = {
      enable = true;
      role = "server";
      tokenFile = clusterConfig.tokenFile;
      extraFlags = toString [
        "--https-listen-port=6444"
        "--tls-san=${clusterConfig.clusterIpAddress}"
        "--node-name=${hostName}"
        "--disable=traefik,servicelb"
        "--node-label=node-group=control-plane"
        "--etcd-arg=quota-backend-bytes=8589934592"
        "--etcd-arg=max-wals=5"
        "--etcd-arg=auto-compaction-mode=periodic"
        "--etcd-arg=auto-compaction-retention=30m"
        "--etcd-arg=snapshot-count=10000"
      ] ++ (if cfg.isInit then clusterInitFlags else [ ]);
    } // lib.optionalAttrs (!cfg.isInit) {
      serverAddr = "https://${clusterConfig.clusterIpAddress}:6443";
    };
  };
}

{ lib, config, clusterConfig, hostName, ... }:

let
  cfg = config.roles.k8sWorker;
in
{
  options.roles.k8sWorker = {
    enable = lib.mkEnableOption "Enable Kubernetes worker node role";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
    networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;

    services.k3s = {
      enable = true;
      role = "agent";
      extraFlags = toString [
        "--node-name=${hostName}"
        "--node-label=node-group=worker"
      ];
      tokenFile = clusterConfig.tokenFile;
      serverAddr = "https://${clusterConfig.clusterIpAddress}:6443";
    };
  };
}

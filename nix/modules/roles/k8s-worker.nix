{ clusterConfig, hostName, ... }:

let
  initFlags = [
    "--tls-san=${clusterConfig.clusterIpAddress}"
    "--node-name=${hostName}"
    "--node-label=node-group=worker"
  ];
in
{
  networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
  networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;

  services.k3s = {
    enable = true;
    role = "agent";
    extraFlags = toString initFlags;
    tokenFile = clusterConfig.tokenFile;
    serverAddr = "https://${clusterConfig.clusterIpAddress}:6443";
  };
}

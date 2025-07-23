{ clusterConfig, hostName, ... }:

let
  masterHostname = builtins.head clusterConfig.masters;
  serverAddress = clusterConfig.hosts.${masterHostname}.ipAddress;
  initFlags = [
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
    serverAddr = "https://${serverAddress}:6443";
  };
}

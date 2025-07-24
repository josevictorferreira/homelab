{ lib, hostName, clusterConfig, ... }:

let
  masterHostname = builtins.head clusterConfig.masters;
  serverAddress = clusterConfig.hosts.${masterHostname}.ipAddress;
  isInit = hostName == masterHostname;
  clusterInitFlags = [
    "--cluster-init"
    "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule"
  ];
  initFlags = [
    "--node-name=${hostName}"
    "--disable=traefik,servicelb"
    "--node-label=node-group=master"
  ] ++ (if isInit then clusterInitFlags else [ ]);
in
{
  networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
  networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = clusterConfig.tokenFile;
    extraFlags = toString initFlags;
  } // lib.optionalAttrs (!isInit) {
    serverAddr = "https://${serverAddress}:6443";
  };
}

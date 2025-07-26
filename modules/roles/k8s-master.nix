{ lib, hostName, clusterConfig, ... }:

let
  masterHostname = builtins.head clusterConfig.masters;
  isInit = hostName == masterHostname;
  clusterInitFlags = [
    "--cluster-init"
    "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule"
  ];
  initFlags = [
    "--tls-san=${clusterConfig.clusterIpAddress}"
    "--node-name=${hostName}"
    "--disable=traefik,servicelb"
    "--node-label=node-group=master"
    "--etcd-arg=quota-backend-bytes=8589934592"
    "--etcd-arg=max-wals=5"
  ] ++ (if isInit then clusterInitFlags else [ ]);
in
{
  imports = [
    ./../services/haproxy-k8s-api.nix
    ./../services/keepalived-k8s.nix
  ];

  networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose ++ [ 6443 ];
  networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose ++ [ 6443 ];

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = clusterConfig.tokenFile;
    extraFlags = toString initFlags;
  } // lib.optionalAttrs (!isInit) {
    serverAddr = "https://${clusterConfig.clusterIpAddress}:6443";
  };
}

{ lib, pkgs, hostName, clusterConfig, ... }:

let
  masterHostname = builtins.head clusterConfig.masters;
  isInit = hostName == masterHostname;
  clusterInitFlags = [
    "--cluster-init"
    "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule"
  ];
  initFlags = [
    "--https-listen-port=6444"
    "--tls-san=${clusterConfig.clusterIpAddress}"
    "--node-name=${hostName}"
    "--disable=traefik,servicelb"
    "--node-label=node-group=master"
    "--etcd-arg=quota-backend-bytes=8589934592"
    "--etcd-arg=max-wals=5"
    "--etcd-arg=auto-compaction-mode=periodic"
    "--etcd-arg=auto-compaction-retention=30m"
    "--etcd-arg=snapshot-count=10000"
  ] ++ (if isInit then clusterInitFlags else [ ]);
in
{
  imports = [
    ./../services/haproxy-k8s-api.nix
    ./../services/keepalived-k8s.nix
  ];

  environment.systemPackages = with pkgs; [
    xfsprogs
  ];

  fileSystems."/var/lib/rancher/k3s/server/db" = {
    device = "/dev/disk/by-label/k3sdb";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" "space_cache=v2" ];
  };

  networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
  networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = clusterConfig.tokenFile;
    extraFlags = toString initFlags;
  } // lib.optionalAttrs (!isInit) {
    serverAddr = "https://${clusterConfig.clusterIpAddress}:6443";
  };
}

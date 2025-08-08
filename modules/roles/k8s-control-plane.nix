{ lib, config, hostName, clusterConfig, commonsPath, flakeRoot, ... }:

let
  cfg = config.roles.k8sControlPlane;
  clusterInitFlags = [
    "--cluster-init"
  ];
  serverFlagList = [
    "--tls-san=${clusterConfig.ipAddress}"
    "--tls-san=10.10.10.200"
    "--write-kubeconfig-mode \"0644\""
    "--node-name=${hostName}"
    "--disable-helm-controller"
    "--disable-kube-proxy"
    "--disable-network-policy"
    "--flannel-backend=none"
    "--disable=traefik,servicelb,local-storage"
    "--node-label=node-group=control-plane"
    "--etcd-expose-metrics=true"
    "--etcd-snapshot-schedule-cron='0 */12 * * *'"
    "--etcd-arg=quota-backend-bytes=8589934592"
    "--etcd-arg=max-wals=5"
    "--etcd-arg=auto-compaction-mode=periodic"
    "--etcd-arg=auto-compaction-retention=30m"
    "--etcd-arg=snapshot-count=10000"
  ] ++ (if cfg.isInit then clusterInitFlags else [ ]);
in
{
  options.roles.k8sControlPlane = {
    enable = lib.mkEnableOption "Enable Kubernetes control plane role";
    isInit = lib.mkOption {
      type = lib.types.bool;
      default = (builtins.head clusterConfig.nodeGroups.k8sControlPlanes) == hostName;
      description = "Whether this node is the initial control plane node";
    };
  };

  imports = [
    "${commonsPath}/k8s-node-defaults.nix"
  ];

  config = lib.mkIf cfg.enable {
    k8sNodeDefaults.enable = true;

    services.k3s = {
      enable = true;
      role = "server";
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = lib.concatStringsSep " " serverFlagList;
    } // lib.optionalAttrs (!cfg.isInit) {
      serverAddr = "https://${clusterConfig.ipAddress}:6443";
    } // lib.optionalAttrs cfg.isInit {
      manifests = {
        cilium = {
          enable = true;
          target = "cilium.yaml";
          source = "${flakeRoot}/kubernetes/manifests/cilium.yaml";
        };
        kubeVip = {
          enable = true;
          target = "kube-vip.yaml";
          source = "${flakeRoot}/kubernetes/manifests/kube-vip.yaml";
        };
      };
    };

    systemd.tmpfiles.rules = [
      "L+ /opt/cni/bin - - - - /var/lib/rancher/k3s/data/cni/"
      "d /var/lib/rancher/k3s/agent/etc/cni/net.d 0751 root root - -"
      "L+ /etc/cni/net.d - - - - /var/lib/rancher/k3s/agent/etc/cni/net.d"
    ];
  };
}

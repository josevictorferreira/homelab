{ lib, config, hostName, clusterConfig, commonsPath, secretsPath, k8sManifestsPath, ... }:

let
  cfg = config.roles.k8sControlPlane;
  clusterInitFlags = [
    "--cluster-init"
    "--write-kubeconfig-mode 0644"
  ];
  serverFlagList = [
    "--tls-san=${clusterConfig.ipAddress}"
    "--node-name=${hostName}"
    "--disable-helm-controller"
    "--disable-network-policy"
    "--disable-cloud-controller"
    "--disable-kube-proxy"
    "--flannel-backend=none"
    "--disable=traefik,servicelb,local-storage,metrics-server"
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

  config = lib.mkIf cfg.enable
    {
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
            source = "${k8sManifestsPath}/cilium.yaml";
          };
          kubeVip = {
            enable = true;
            target = "kube-vip.yaml";
            source = "${k8sManifestsPath}/kube-vip.yaml";
          };
          flux-components = {
            enable = true;
            target = "gotk-components.yaml";
            source = "${k8sManifestsPath}/flux-system/gotk-components.yaml";
          };
          flux-sync = {
            enable = true;
            target = "gotk-sync.yaml";
            source = "${k8sManifestsPath}/flux-system/gotk-sync.yaml";
          };
          flux-kustomization = {
            enable = true;
            target = "kustomization.yaml";
            source = "${k8sManifestsPath}/flux-system/kustomization.yaml";
          };
        };
      };

      systemd.tmpfiles.rules = [
        "L+ /opt/cni/bin - - - - /var/lib/rancher/k3s/data/cni/"
        "d /var/lib/rancher/k3s/agent/etc/cni/net.d 0751 root root - -"
        "L+ /etc/cni/net.d - - - - /var/lib/rancher/k3s/agent/etc/cni/net.d"
      ];
    } // lib.optionalAttrs cfg.isInit {
    fileSystems."/var/lib/rancher/k3s/server/manifests" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0700" "noexec" "nosuid" "nodev" "size=16M" ];
    };

    sops.secrets.k3s_root_ca_pem = {
      sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/tls/root-ca.pem";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.k3s_root_ca_key = {
      sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/tls/root-ca.key";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.sops_age_secret = {
      sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/manifests/sops-age-secret.yaml";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.flux_system_secret = {
      sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/manifests/flux-system-secret.yaml";
      owner = "root";
      mode = "0400";
    };
  };
}

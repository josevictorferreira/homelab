{ lib, config, hostName, hostConfig, ... }:

let
  serviceEnabled = true;
  clusterConfig = homelab.cluster;
  kubernetesConfig = homelab.kubernetes;
  servicesPath = homelab.paths.services;
  secretsPath = homelab.paths.secrets;
  k8sManifestsPath = homelab.paths.kubernetes;
  cfg = config.profiles."k8s-control-plane";
  clusterInitFlags = [
    "--cluster-init"
    "--write-kubeconfig-mode 0644"
  ];
  initNodeHostName = builtins.head clusterConfig.nodeGroupHostNames.k8sControlPlanes;
  serverFlagList = [
    "--https-listen-port=6444"
    "--tls-san=${kubernetesConfig.vipAddress}"
    "--node-name=${hostName}"
    "--node-ip=${hostConfig.ipAddress}"
    "--advertise-address=${hostConfig.ipAddress}"
    "--disable-helm-controller"
    "--disable-network-policy"
    "--disable-cloud-controller"
    "--disable-kube-proxy"
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
  options.profiles."k8s-control-plane" = {
    enable = lib.mkEnableOption "Enable Kubernetes control plane role";
    isInit = lib.mkOption {
      type = lib.types.bool;
      default =
        (initNodeHostName == hostName);
      description = "Whether this node is the initial control plane node";
    };
  };

  imports = [
    "${servicesPath}/haproxy.nix"
    "${servicesPath}/keepalived.nix"
  ];

  config = lib.mkIf cfg.enable
    {
      sops.secrets.sops_age_secret = lib.mkIf cfg.isInit {
        sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
        path = "/var/lib/rancher/k3s/server/manifests/sops-age-secret.yaml";
        owner = "root";
        mode = "0400";
      };

      sops.secrets.flux_system_secret = lib.mkIf cfg.isInit {
        sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
        path = "/var/lib/rancher/k3s/server/manifests/flux-system-secret.yaml";
        owner = "root";
        mode = "0400";
      };

      services.k3s = {
        enable = serviceEnabled;
        role = "server";
        tokenFile = config.sops.secrets.k3s_token.path;
        extraFlags = lib.concatStringsSep " " serverFlagList;
      } // lib.optionalAttrs (!cfg.isInit) {
        serverAddr = "https://${kubernetesConfig.vipAddress}:6443";
      } // lib.optionalAttrs cfg.isInit {
        manifests =
          {
            cilium = {
              enable = true;
              target = "cilium.yaml";
              source = "${k8sManifestsPath}/system/cilium.yaml";
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
          };
      };

      systemd.tmpfiles.rules = [
        "L+ /opt/cni/bin - - - - /var/lib/rancher/k3s/data/cni/"
        "d /var/lib/rancher/k3s/agent/etc/cni/net.d 0751 root root - -"
        "L+ /etc/cni/net.d - - - - /var/lib/rancher/k3s/agent/etc/cni/net.d"
      ];

      system.activationScripts.k3sReset = lib.mkIf (!config.services.k3s.enable) {
        supportsDryActivation = true;
        text = ''
          systemctl stop k3s.service > /dev/null 2>&1 || true
          umount -R /var/lib/kubelet > /dev/null 2>&1 || true
          sleep 2
          rm -rf /etc/rancher/{k3s,node} > /dev/null 2>&1 || true
          rm -rf /var/lib/{rancher/k3s,kubelet,longhorn,etcd,cni} > /dev/null 2>&1 || true
          if [ -d /opt/k3s/data/temp ]; then
            rm -rf /opt/k3s/data/temp/*
          fi
          sync
          echo -e "\n => reboot now to complete k3s cleanup!"
        '';
      };
    };
}

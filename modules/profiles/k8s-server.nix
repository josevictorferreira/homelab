{ lib, config, pkgs, homelab, ... }:

let
  cfg = config.profiles."k8s-server";
  usersConfig = homelab.users;
  secretsPath = homelab.paths.secrets;
  username = config.users.users.${usersConfig.admin.username}.name;
in
{
  options.profiles."k8s-server" = {
    enable = lib.mkEnableOption "Enable the node to be a Kubernetes server node";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.k3s_token = {
      sopsFile = "${secretsPath}/k8s-secrets.enc.yaml";
      owner = username;
      mode = "0400";
    };

    environment.systemPackages = with pkgs; [
      cilium-cli
      fluxcd
      iptables
      bpftools
      vals
      util-linux

      (writeShellScriptBin "nuke-k3s" ''
        if [ "$EUID" -ne 0 ] ; then
          echo "Please run as root"
          exit 1
        fi
        read -r -p 'Nuke k3s?, confirm with yes (y/N): ' choice
        case "$choice" in
          y|Y|yes|Yes) echo "nuke k3s...";;
          *) exit 0;;
        esac
        /run/current-system/sw/bin/k3s-killall.sh
        systemctl disable k3s
        KUBELET_PATH=$(mount | grep kubelet | cut -d' ' -f3);
        /$/{KUBELET_PATH:+umount /$KUBELET_PATH/}
        sleep 2
        rm -rf /etc/rancher/{k3s,node}
        rm -rf /var/lib/{rancher/k3s,kubelet,longhorn,etcd,cni}
        if [ -d /opt/k3s/data/temp ]; then
          rm -rf /opt/k3s/data/temp/*
        fi
        sync
        echo -e "\n => reboot now to complete k3s cleanup!"
        sleep 3
        reboot
      '')
    ];

    boot.kernelModules = [
      "br_netfilter"
      "nft-expr-counter"
      "iptable_nat"
      "iptable_filter"
      "nft_counter"
      "ip6_tables"
      "ip6table_mangle"
      "ip6table_raw"
      "ip6table_filter"
      "ip_conntrack"
      "ip_vs"
      "ip_vs_rr"
      "ip_vs_wrr"
      "ip_vs_sh"
    ];

    boot.kernel.sysctl = {
      "fs.inotify.max_user_instances" = 8192;
      "fs.inotify.max_user_watches" = 524288;
    };

    networking.enableIPv6 = true;
    networking.nat = {
      enable = true;
      enableIPv6 = true;
    };

    networking.firewall.allowedTCPPorts = [
      443
      2379
      2380
      4240
      6443
      6444
      8472
      10250
    ];
    networking.firewall.allowedUDPPorts = [
      8472
      51820
      51821
    ];
  };
}

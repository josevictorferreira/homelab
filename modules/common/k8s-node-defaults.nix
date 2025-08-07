{ lib, pkgs, config, clusterConfig, usersConfig, flakeRoot, ... }:

let
  cfg = config.k8sNodeDefaults;
  username = config.users.users.${usersConfig.admin.username}.name;
in
{
  options.k8sNodeDefaults = {
    enable = lib.mkEnableOption "Enable base configurations for k3s nodes";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.k3s_token = {
      owner = username;
      mode = "0400";
    };

    environment.systemPackages = with pkgs; [
      cilium-cli
      fluxcd
      ceph-client

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
        flux uninstall -s || true
        kubectl delete deployments --all=true -A
        kubectl delete statefulsets --all=true -A  
        kubectl delete ns --all=true -A
        kubectl get ns | tail -n +2 | cut -d ' ' -f 1 | xargs -I{} kubectl delete pods --all=true --force=true -n {}
        timeout 10 kubectl delete crds --all || true
        cilium uninstall || true
        echo "wait until objects are deleted..."
        sleep 28
        /run/current-system/sw/bin/k3s-killall.sh
        systemctl stop k3s
        sleep 2
        rm -rf /var/lib/rancher/k3s/
        rm -rf /var/lib/cni/networks/cbr0/
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
      "ceph"
      "rbd"
      "nfs"
      "nft-expr-counter"
      "iptable_nat"
      "iptable_filter"
      "nft_counter"
      "ip6_tables"
      "ip6table_mangle"
      "ip6table_raw"
      "ip6table_filter"
      "ip_vs"
      "ip_vs_rr"
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

    networking.firewall.allowedTCPPorts = clusterConfig.portsTcpToExpose;
    networking.firewall.allowedUDPPorts = clusterConfig.portsUdpToExpose;
  };
}

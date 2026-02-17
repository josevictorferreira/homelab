{ lib
, config
, pkgs
, hostName
, hostConfig
, homelab
, ...
}:

let
  serviceEnabled = true;
  cfg = config.profiles."k8s-control-plane";
  clusterInitFlags = [
    "--cluster-init"
    "--write-kubeconfig-mode 0644"
  ];
  roleLabelFlags = map (role: "--node-label=node.kubernetes.io/${role}=true") hostConfig.roles;
  initNodeHostName = builtins.head homelab.nodes.group."k8s-control-plane".names;
  serverFlagList = [
    "--https-listen-port=6444"
    "--tls-san=${homelab.kubernetes.vipAddress}"
    "--node-name=${hostName}"
    "--node-ip=${hostConfig.ipAddress}"
    "--advertise-address=${hostConfig.ipAddress}"
    "--disable-helm-controller"
    "--disable-network-policy"
    "--disable-cloud-controller"
    "--disable-kube-proxy"
    "--flannel-backend=none"
    "--disable=traefik,servicelb,local-storage"
    "--etcd-expose-metrics=true"
    "--etcd-snapshot-schedule-cron='0 */12 * * *'"
    "--etcd-arg=quota-backend-bytes=8589934592"
    "--etcd-arg=max-wals=5"
    "--etcd-arg=auto-compaction-mode=periodic"
    "--etcd-arg=auto-compaction-retention=30m"
  ]
  ++ (if cfg.isInit then clusterInitFlags else [ ])
  ++ roleLabelFlags;
  bootstrapManifestFiles = builtins.attrNames (
    builtins.readDir "${homelab.paths.manifests}/bootstrap"
  );
in
{
  options.profiles."k8s-control-plane" = {
    enable = lib.mkEnableOption "Enable Kubernetes control plane role";
    isInit = lib.mkOption {
      type = lib.types.bool;
      default = (initNodeHostName == hostName);
      description = "Whether this node is the initial control plane node";
    };
  };

  imports = [
    "${homelab.paths.services}/haproxy.nix"
    "${homelab.paths.services}/keepalived.nix"
  ];

  config = lib.mkIf cfg.enable {
    sops.secrets.sops_age_secret = lib.mkIf cfg.isInit {
      sopsFile = "${homelab.paths.secrets}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/manifests/sops-age-secret.yaml";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.flux_system_secret = lib.mkIf cfg.isInit {
      sopsFile = "${homelab.paths.secrets}/k8s-secrets.enc.yaml";
      path = "/var/lib/rancher/k3s/server/manifests/flux-system-secret.yaml";
      owner = "root";
      mode = "0400";
    };

    # MinIO credentials for etcd snapshot offload
    sops.secrets.minio_etcd_access_key_id = {
      owner = "root";
      mode = "0400";
    };
    sops.secrets.minio_etcd_secret_access_key = {
      owner = "root";
      mode = "0400";
    };

    services.k3s = {
      enable = serviceEnabled;
      role = "server";
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = lib.concatStringsSep " " serverFlagList;
    }
    // lib.optionalAttrs (!cfg.isInit) {
      serverAddr = "https://${homelab.kubernetes.vipAddress}:6443";
    }
    // lib.optionalAttrs cfg.isInit {
      manifests =
        builtins.listToAttrs
          (
            map
              (fileName: {
                name = fileName;
                value = {
                  enable = true;
                  target = fileName;
                  source = "${homelab.paths.manifests}/bootstrap/${fileName}";
                };
              })
              bootstrapManifestFiles
          )
        // {
          cilium = {
            enable = true;
            target = "cilium.yaml";
            source = "${homelab.paths.manifests}/system/cilium.yaml";
          };
          flux-components = {
            enable = true;
            target = "gotk-components.yaml";
            source = "${homelab.paths.manifests}/flux-system/gotk-components.yaml";
          };
          flux-sync = {
            enable = true;
            target = "gotk-sync.yaml";
            source = "${homelab.paths.manifests}/flux-system/gotk-sync.yaml";
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

    systemd.timers.k3s-etcd-offload = {
      description = "Upload k3s etcd snapshots to MinIO";
      wantedBy = [ "timers.target" ];
      after = [ "k3s.service" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };

    systemd.services.k3s-etcd-offload = {
      description = "Upload k3s etcd snapshots to MinIO";
      after = [ "k3s.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ReadOnlyPaths = [ "/var/lib/rancher/k3s/server/db/snapshots" ];
        Environment = "MC_CONFIG_DIR=/run/k3s-etcd-offload";
        RuntimeDirectory = "k3s-etcd-offload";
      };
      path = [
        pkgs.minio-client
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.getent
      ];
      script = ''
        set -euo pipefail

        SNAPSHOT_DIR="/var/lib/rancher/k3s/server/db/snapshots"
        HOSTNAME=$(hostname)
        MINIO_ENDPOINT="http://10.10.10.209:9000"
        BUCKET="homelab-backup-etcd"
        STATE_FILE="/var/lib/k3s-etcd-offload/uploaded.list"

        # Read MinIO creds from sops-nix secrets
        AK=$(cat /run/secrets/minio_etcd_access_key_id)
        SK=$(cat /run/secrets/minio_etcd_secret_access_key)

        # Configure mc
        mc alias set etcd "''${MINIO_ENDPOINT}" "''${AK}" "''${SK}"

        # Ensure state dir exists
        mkdir -p /var/lib/k3s-etcd-offload
        touch "''${STATE_FILE}"

        # Find snapshot files (skip files modified in last 60s to avoid uploading in-progress snapshots)
        find "''${SNAPSHOT_DIR}" -type f -name '*.db' -not -newermt '60 seconds ago' | sort | while read -r SNAP; do
          BASENAME=$(basename "''${SNAP}")

          # Skip if already uploaded
          if grep -qxF "''${BASENAME}" "''${STATE_FILE}"; then
            echo "SKIP: ''${BASENAME} (already uploaded)"
            continue
          fi

          echo "Uploading: ''${BASENAME}"

          # Compute sha256
          sha256sum "''${SNAP}" > "/tmp/''${BASENAME}.sha256"

          # Upload snapshot + checksum
          mc cp "''${SNAP}" "etcd/''${BUCKET}/''${HOSTNAME}/''${BASENAME}"
          mc cp "/tmp/''${BASENAME}.sha256" "etcd/''${BUCKET}/''${HOSTNAME}/''${BASENAME}.sha256"
          rm -f "/tmp/''${BASENAME}.sha256"

          # Record as uploaded
          echo "''${BASENAME}" >> "''${STATE_FILE}"
          echo "OK: ''${BASENAME} uploaded"
        done

        # Prune state file: keep only entries for snapshots that still exist locally
        TEMP=$(mktemp)
        while IFS= read -r line; do
          if [ -f "''${SNAPSHOT_DIR}/''${line}" ]; then
            echo "''${line}"
          fi
        done < "''${STATE_FILE}" > "''${TEMP}"
        mv "''${TEMP}" "''${STATE_FILE}"

        echo "=== etcd offload complete ==="
      '';
    };
  };
}

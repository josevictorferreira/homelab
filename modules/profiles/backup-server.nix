{
  lib,
  config,
  pkgs,
  hostName,
  homelab,
  ...
}:

let
  cfg = config.profiles."backup-server";
  servicesPath = homelab.paths.services;
  wolMachines = lib.attrsets.filterAttrs (name: _: name != hostName) homelab.nodes.hosts;
  wolMachinesList = lib.attrValues (
    lib.mapAttrs (name: value: value // { inherit name; }) wolMachines
  );
in
{
  options.profiles."backup-server" = {
    enable = lib.mkEnableOption "Enable backup target role";
  };

  imports = [
    "${servicesPath}/wake-on-lan-observer.nix"
    "${servicesPath}/minio.nix"
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      zfs
      minio-client
    ];

    boot.supportedFilesystems = [ "zfs" ];

    # Non-blocking ZFS pool import — polls for USB device up to 180s.
    # Replaces boot.zfs.extraPools which blocks boot if device is missing.
    systemd.services.zpool-import-backup = {
      description = "Import ZFS backup-pool (non-blocking, waits for USB)";
      after = [
        "systemd-udev-settle.service"
        "systemd-modules-load.service"
      ];
      wants = [ "systemd-udev-settle.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = with pkgs; [
        zfs
        gnugrep
        coreutils
      ];
      script = ''
        # Already imported — nothing to do
        if zpool list backup-pool &>/dev/null; then
          echo "backup-pool already imported"
          zfs set mountpoint=none backup-pool 2>/dev/null || true
          zfs set mountpoint=/mnt/backups backup-pool/data 2>/dev/null || true
          zfs mount -a 2>/dev/null || true
          mkdir -p /mnt/backups/minio && chown minio:minio /mnt/backups/minio
          exit 0
        fi

        # Poll for USB device up to 180 seconds
        for i in $(seq 1 180); do
          if zpool import -d /dev/disk/by-id 2>/dev/null | grep -q "backup-pool"; then
            echo "backup-pool found, importing..."
            if zpool import -d /dev/disk/by-id -f backup-pool; then
              echo "Pool imported, setting mountpoint..."
              zfs set mountpoint=none backup-pool
              zfs set mountpoint=/mnt/backups backup-pool/data
              zfs mount -a 2>/dev/null || true
              mkdir -p /mnt/backups/minio && chown minio:minio /mnt/backups/minio
              exit 0
            fi
            echo "Import attempt failed, retrying..."
          fi
          sleep 1
        done

        echo "WARNING: backup-pool not found after 180s" >&2
        exit 1
      '';
    };

    services.nfs.server = {
      enable = true;
      exports = ''
        /mnt/backups *(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    services.minioCustom = {
      enable = true;
      dataDir = "/mnt/backups/minio";
      rootCredentialsFile = "/run/secrets/minio_credentials";
    };

    # MinIO only starts after ZFS pool is imported and mounted
    systemd.services.minio = {
      after = [ "zpool-import-backup.service" ];
      requires = [ "zpool-import-backup.service" ];
    };

    # Boot-only oneshot: provisions MinIO buckets, policies, per-service creds
    systemd.services.minio-bootstrap = {
      description = "Provision MinIO buckets, policies and per-service credentials";
      after = [
        "minio.service"
        "zpool-import-backup.service"
        "network-online.target"
      ];
      requires = [
        "minio.service"
        "zpool-import-backup.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = "/run/secrets/minio_credentials";
        RuntimeDirectory = "minio-bootstrap";
        Environment = "MC_CONFIG_DIR=/run/minio-bootstrap";
      };
      path = with pkgs; [
        minio-client
        curl
        coreutils
        jq
      ];
      script = ''
        ## Wait for MinIO readiness (up to 60s)
        for i in $(seq 1 60); do
          if curl -sf http://127.0.0.1:9000/minio/health/ready >/dev/null 2>&1; then
            echo "MinIO ready"
            break
          fi
          if [ "$i" -eq 60 ]; then
            echo "ERROR: MinIO not ready after 60s" >&2
            exit 1
          fi
          sleep 1
        done

        ## Admin connection via env (no alias file with creds on disk)
        export MC_HOST_pi="http://''${MINIO_ROOT_USER}:''${MINIO_ROOT_PASSWORD}@127.0.0.1:9000"

        BUCKETS="homelab-backup-velero homelab-backup-postgres homelab-backup-rgw homelab-backup-etcd"

        ## Create buckets (idempotent)
        for b in $BUCKETS; do
          mc mb "pi/$b" --ignore-existing || true
          echo "Bucket $b OK"
        done

        ## ILM expiry 14d per bucket
        for b in $BUCKETS; do
          # Enable versioning (required for some ILM features)
          mc version enable "pi/$b" 2>/dev/null || true

          # Remove existing expire-14d rule if present, then re-add
          mc ilm rule rm "pi/$b" --id "expire-14d" 2>/dev/null || true
          mc ilm rule add "pi/$b" \
            --id "expire-14d" \
            --expiry-days 14 \
            --noncurrent-expire-days 14 || true
          echo "ILM expire-14d on $b OK"
        done

        ## Per-service creds + policies
        SERVICES="velero postgres rgw etcd"
        for svc in $SERVICES; do
          BUCKET="homelab-backup-$svc"
          AK_FILE="/run/secrets/minio_''${svc}_access_key_id"
          SK_FILE="/run/secrets/minio_''${svc}_secret_access_key"

          AK=$(cat "$AK_FILE")
          SK=$(cat "$SK_FILE")

          POLICY_NAME="''${svc}-backup-rw"

          # Write scoped policy JSON
          cat > "/run/minio-bootstrap/''${POLICY_NAME}.json" <<POLICY
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads"
              ],
              "Resource": ["arn:aws:s3:::$BUCKET"]
            },
            {
              "Effect": "Allow",
              "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
              ],
              "Resource": ["arn:aws:s3:::$BUCKET/*"]
            }
          ]
        }
        POLICY

          # Create/update policy
          mc admin policy create pi "$POLICY_NAME" "/run/minio-bootstrap/''${POLICY_NAME}.json" 2>/dev/null || \
            mc admin policy create pi "$POLICY_NAME" "/run/minio-bootstrap/''${POLICY_NAME}.json"
          echo "Policy $POLICY_NAME OK"

          # Enforce user state: remove + recreate to handle secret rotation
          mc admin user remove pi "$AK" 2>/dev/null || true
          mc admin user add pi "$AK" "$SK"
          echo "User $AK created"

          # Attach policy
          mc admin policy attach pi "$POLICY_NAME" --user "$AK"
          echo "Policy $POLICY_NAME attached to $AK"
        done

        echo "MinIO bootstrap complete"
      '';
    };

    services.wakeOnLanObserver = {
      enable = true;
      machines = wolMachinesList;
    };

    # Override nixos-server's firewall.enable = false
    networking.firewall.enable = lib.mkForce true;

    # MinIO API+console: LAN interface only (end0)
    networking.firewall.interfaces.end0.allowedTCPPorts = [
      9000
      9001
      2049
      111
    ];
    networking.firewall.interfaces.end0.allowedUDPPorts = [
      2049
      111
    ];

    # Per-service MinIO credentials — materialized as /run/secrets/*
    sops.secrets = {
      minio_velero_access_key_id.mode = "0400";
      minio_velero_secret_access_key.mode = "0400";
      minio_postgres_access_key_id.mode = "0400";
      minio_postgres_secret_access_key.mode = "0400";
      minio_rgw_access_key_id.mode = "0400";
      minio_rgw_secret_access_key.mode = "0400";
      minio_etcd_access_key_id.mode = "0400";
      minio_etcd_secret_access_key.mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d /mnt/backups 0755 root root -"
    ];
  };
}

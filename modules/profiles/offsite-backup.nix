{ lib
, config
, pkgs
, homelab
, ...
}:

let
  cfg = config.profiles."offsite-backup";
  servicesPath = homelab.paths.services;

  # Primary backup MinIO on lab-pi-bk, reached through the Tailscale subnet routers.
  sourceHost = "10.10.10.209:9000";
  pushgatewayUrl = "http://${homelab.kubernetes.loadBalancer.services.pushgateway}:9091";

  # Buckets pulled from the primary. mc mirror copies current versions only,
  # so sizes here are far below the source's on-disk usage (which includes
  # noncurrent versions). Check `mc du` totals stay well under the 200GB disk.
  mirrorBuckets = [
    "homelab-backup-velero"
    "homelab-backup-postgres"
    "homelab-backup-etcd"
    "homelab-backup-rgw"
    "homelab-backup-shared"
  ];
in
{
  options.profiles."offsite-backup" = {
    enable = lib.mkEnableOption "Off-site pull mirror of the primary backup MinIO";
  };

  imports = [
    "${servicesPath}/minio.nix"
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.minio-client ];

    services.minioCustom = {
      enable = true;
      dataDir = "/var/lib/minio";
      rootCredentialsFile = "/run/secrets/minio_credentials";
    };

    # Daily pull mirror. Also provisions buckets idempotently on every run:
    # versioning + 14d noncurrent expiry give a rollback window if the source
    # is wiped and --remove propagates the deletions here.
    systemd.services.minio-offsite-mirror = {
      description = "Mirror primary backup buckets from lab-pi-bk MinIO";
      after = [
        "minio.service"
        "network-online.target"
      ];
      requires = [ "minio.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "/run/secrets/minio_credentials";
        RuntimeDirectory = "minio-offsite-mirror";
        Environment = "MC_CONFIG_DIR=/run/minio-offsite-mirror";
      };
      path = with pkgs; [
        minio-client
        curl
        coreutils
        getent # required by mc to resolve config dir
      ];
      script = ''
        for i in $(seq 1 60); do
          if curl -sf http://127.0.0.1:9000/minio/health/ready >/dev/null 2>&1; then
            break
          fi
          if [ "$i" -eq 60 ]; then
            echo "ERROR: local MinIO not ready after 60s" >&2
            exit 1
          fi
          sleep 1
        done

        export MC_HOST_pi="http://''${MINIO_ROOT_USER}:''${MINIO_ROOT_PASSWORD}@${sourceHost}"
        export MC_HOST_oci="http://''${MINIO_ROOT_USER}:''${MINIO_ROOT_PASSWORD}@127.0.0.1:9000"

        for b in ${lib.concatStringsSep " " mirrorBuckets}; do
          mc mb "oci/$b" --ignore-existing
          mc version enable "oci/$b" 2>/dev/null || true
          mc ilm rule add --noncurrent-expire-days 14 "oci/$b" 2>/dev/null || true

          echo "Mirroring $b ..."
          mc mirror --overwrite --remove --quiet "pi/$b" "oci/$b"
        done

        echo "Off-site mirror complete"

        # Heartbeat for the "Off-site Mirror Staleness" alert (pushgateway in the
        # cluster, reached over the Tailscale subnet route). Best effort.
        echo "offsite_mirror_last_success_timestamp_seconds $(date +%s)" \
          | curl -sf --max-time 30 --data-binary @- \
              "${pushgatewayUrl}/metrics/job/minio-offsite-mirror/instance/lab-oci-bk" \
          || echo "WARN: heartbeat push to pushgateway failed" >&2
      '';
    };

    systemd.timers.minio-offsite-mirror = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # After the nightly velero (03:00) and postgres backups have landed
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };
}

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
      path = [
        pkgs.zfs
        pkgs.gnugrep
      ];
      script = ''
        # Already imported — nothing to do
        if zpool list backup-pool &>/dev/null; then
          echo "backup-pool already imported"
          exit 0
        fi

        # Poll for USB device up to 180 seconds
        for i in $(seq 1 180); do
          if zpool import -d /dev/disk/by-id 2>/dev/null | grep -q "backup-pool"; then
            echo "backup-pool found, importing..."
            zpool import -d /dev/disk/by-id -N backup-pool && exit 0
            echo "Import attempt failed, retrying..."
          fi
          sleep 1
        done

        echo "WARNING: backup-pool not found after 180s" >&2
        exit 1
      '';
    };

    # Mount with nofail — boot NEVER blocks on this
    fileSystems."/mnt/backups" = {
      device = "backup-pool";
      fsType = "zfs";
      options = [
        "nofail"
        "noauto"
        "x-systemd.requires=zpool-import-backup.service"
        "x-systemd.after=zpool-import-backup.service"
      ];
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

    # MinIO only starts after ZFS mount succeeds
    systemd.services.minio = {
      after = [
        "mnt-backups.mount"
        "zpool-import-backup.service"
      ];
      requires = [ "mnt-backups.mount" ];
    };

    services.wakeOnLanObserver = {
      enable = true;
      machines = wolMachinesList;
    };

    networking.firewall.allowedTCPPorts = [
      2049
      111
    ];
    networking.firewall.allowedUDPPorts = [
      2049
      111
    ];

    systemd.tmpfiles.rules = [
      "d /mnt/backups 0755 root root -"
    ];
  };
}

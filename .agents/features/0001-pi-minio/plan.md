# Technical Implementation Plan: Pi MinIO Configuration

## 1. Executive Summary
Configure Raspberry Pi (`lab-pi-bk`) as MinIO object storage server. The Pi has an external USB SanDisk drive with an existing ZFS pool (`backup-pool`). Due to an underpowered PSU, USB devices appear late (seconds to minutes after boot). This plan ensures **boot never blocks** on USB availability while still using ZFS.

**Key constraint**: MUST NOT change kernel params, initrd, or bootloader config — a failed boot is unrecoverable without a working keyboard (also affected by USB power issue).

## 2. Architecture & Design

### 2.1 Component Structure
*   **Profile**: `modules/profiles/backup-server.nix`
    *   Responsibilities:
        *   Custom non-blocking systemd service to import ZFS pool `backup-pool` when USB appears.
        *   Mount `backup-pool` to `/mnt/backups` with `nofail`.
        *   Configure MinIO service (depends on mount).
        *   Update NFS exports to `/mnt/backups`.
*   **Service Module**: `modules/services/minio.nix`
    *   No structural changes, just `dataDir` configuration.

### 2.2 USB Device Timeline
```
Boot start ──► System ready ──► USB device enumerated (10-120s) ──► ZFS import ──► Mount ──► MinIO starts
                    │
                    └── Boot completes here (never waits for USB)
```

### 2.3 Data Models & State
*   **Storage Path**: `/mnt/backups`
*   **MinIO Data**: `/mnt/backups/minio`
*   **Filesystem**: ZFS (existing `backup-pool` on USB drive)

### 2.4 Configuration Source of Truth
```nix
# modules/profiles/backup-server.nix
{
  config = lib.mkIf cfg.enable {
    # -- REMOVED: boot.zfs.extraPools (blocks boot if device missing) --

    # Keep ZFS support (already in hardware config)
    boot.supportedFilesystems = [ "zfs" ];

    # Custom non-blocking ZFS pool import
    systemd.services.zpool-import-backup = {
      description = "Import ZFS backup-pool (non-blocking, waits for USB)";
      after = [ "systemd-udev-settle.service" "zfs.target" ];
      wants = [ "systemd-udev-settle.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Poll for USB device up to 180 seconds
        for i in $(seq 1 180); do
          if ${pkgs.zfs}/bin/zpool import -d /dev/disk/by-id 2>/dev/null | grep -q "backup-pool"; then
            ${pkgs.zfs}/bin/zpool import -d /dev/disk/by-id -N backup-pool && exit 0
          fi
          # Check if already imported
          ${pkgs.zfs}/bin/zpool list backup-pool &>/dev/null && exit 0
          sleep 1
        done
        echo "WARNING: backup-pool not found after 180s" >&2
        exit 1
      '';
    };

    # Mount with nofail — boot NEVER blocks
    fileSystems."/mnt/backups" = {
      device = "backup-pool";
      fsType = "zfs";
      options = [ "nofail" "noauto" "x-systemd.requires=zpool-import-backup.service" ];
    };

    # MinIO depends on mount
    services.minioCustom = {
      enable = true;
      dataDir = "/mnt/backups/minio";
    };
    systemd.services.minio = {
      after = [ "mnt-backups.mount" "zpool-import-backup.service" ];
      requires = [ "mnt-backups.mount" ];
    };
  };
}
```

## 3. Implementation Strategy

### Phase 1: Safe ZFS Import (Non-Blocking)
*   **Goal**: Import `backup-pool` without risking boot failure.
*   **Key Changes** in `modules/profiles/backup-server.nix`:
    *   **Remove** `boot.zfs.extraPools = [ "backup-pool" ]` (blocks boot for 60s then fails).
    *   **Add** custom `systemd.services.zpool-import-backup`:
        *   Polls `/dev/disk/by-id` for up to 180s waiting for USB device.
        *   Imports pool with `-N` (no auto-mount, we manage mount separately).
        *   Checks if already imported (idempotent).
        *   Failure is non-fatal to boot.
    *   **Add** `fileSystems."/mnt/backups"` with `nofail` + `noauto` + systemd dependency on import service.
*   **Boot safety**:
    *   `noauto` → mount not required by local-fs.target → boot continues.
    *   `nofail` → mount failure doesn't block boot.
    *   No kernel/initrd/bootloader changes.

### Phase 2: MinIO Service Configuration
*   **Goal**: Run MinIO on `/mnt/backups/minio`, only after mount succeeds.
*   **Key Changes**:
    *   `services.minioCustom.dataDir = "/mnt/backups/minio"`.
    *   `systemd.services.minio.after = [ "mnt-backups.mount" ]`.
    *   `systemd.services.minio.requires = [ "mnt-backups.mount" ]`.
*   MinIO won't start if USB never appears — safe and desired.

### Phase 3: NFS Export Update
*   Update `services.nfs.server.exports` path from `/backups` to `/mnt/backups`.
*   NFS also depends on mount availability.

## 4. Risk Assessment & Mitigation

### 4.1 Boot Safety (CRITICAL)
*   **Risk**: ZFS import blocking boot.
*   **Mitigation**: `noauto` + `nofail` + custom service = boot ALWAYS completes. Worst case: USB never appears → MinIO doesn't start → Pi fully functional otherwise.
*   **What we do NOT change**: kernel params, initrd modules, bootloader, config.txt.

### 4.2 USB Power / config.txt
*   **Finding**: `usb_max_current_enable=1` does NOT apply to Pi 4B (Pi 2/3 only). Pi 4B already provides max 1.2A via VL805 USB controller. No firmware fix available.
*   **Mitigation**: 180s polling timeout handles the delay. For permanent hardware fix, a **powered USB hub** (~$15) is recommended.

### 4.3 ZFS Mount Path Conflict
*   **Risk**: If `backup-pool` has `mountpoint` property set to `/backups`, NixOS `fileSystems` may conflict.
*   **Mitigation**: Import with `-N` (no auto-mount), then mount via systemd. If ZFS `mountpoint` property conflicts, run `zfs set mountpoint=/mnt/backups backup-pool` once on Pi (one-time manual step).

### 4.4 Data Availability
*   **Risk**: Path change from `/backups` to `/mnt/backups`.
*   **Mitigation**: Update NFS exports and MinIO config simultaneously in same deployment.

### 4.5 Existing Data
*   Pool exists with data. NOT formatting. Import-only.

## 5. Verification Plan

### Pre-Deployment
*   `make check` — Nix flake evaluation passes.
*   Review generated systemd units for correct dependencies.

### Post-Deployment
*   `systemctl status zpool-import-backup` — active (exited).
*   `zpool status backup-pool` — pool imported and healthy.
*   `mount | grep mnt/backups` — ZFS mounted.
*   `curl http://10.10.10.209:9000/minio/health/live` — MinIO responding.
*   **Reboot test**: Reboot Pi, verify boot completes within normal time, then USB mount + MinIO come up after delay.

## 6. Hardware Recommendation
A **powered USB hub** (USB 3.0 hub with external power adapter, ~$15) permanently solves the USB power issue. The Pi's 1.2A shared across all USB ports is insufficient for the SanDisk drive at boot. A powered hub provides dedicated power, making the device available immediately.

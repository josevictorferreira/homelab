# Implementation Tasks: Pi MinIO Configuration

## Phase 1: Storage Configuration
Goal: Ensure external drive mounts consistently at `/mnt/backups` and NFS exports are updated.

- [x] **Context Gather**: Read `modules/profiles/backup-server.nix` to understand current filesystem and NFS config. <!-- id: 0 -->
- [x] **Filesystem Definition**: Custom `zpool-import-backup` systemd service replaces `fileSystems` — polls for USB device, force-imports ZFS pool, sets mountpoint on `backup-pool/data` to `/mnt/backups`, mounts via `zfs mount -a`. ZFS native mountpoints can't use fstab. <!-- id: 1 -->
- [x] **Update NFS Exports**: NFS exports point to `/mnt/backups` with rw,sync,no_subtree_check,no_root_squash. <!-- id: 2 -->
- [x] **Tmpfiles Rules**: `d /mnt/backups 0755 root root -` for pre-mount dir. Post-mount `mkdir -p /mnt/backups/minio && chown minio:minio` in import script ensures dir exists on ZFS after mount. <!-- id: 3 -->
- [x] **Lint Check**: `make format` applied, `make lint` passes for backup-server.nix. <!-- id: 4 -->
- [x] **Build Verification**: `make check` passes. <!-- id: 5 -->

## Phase 2: MinIO Service Configuration
Goal: Configure MinIO to use the new storage location.

- [x] **Update Data Dir**: `services.minioCustom.dataDir = "/mnt/backups/minio"`. <!-- id: 6 -->
- [x] **Ensure HTTP**: MinIO listens on `0.0.0.0:9000` (API) and `0.0.0.0:9001` (WebUI), no TLS. <!-- id: 7 -->
- [x] **Lint Check**: `make format` + `make lint` passes. <!-- id: 8 -->
- [x] **Final Build Verification**: `make check` passes. <!-- id: 9 -->

## Phase 3: Final Verification
Goal: Confirm the setup matches the requirements.

- [x] **Review**: `config/nodes.nix` assigns `backup-server` role to `lab-pi-bk`. <!-- id: 10 -->
- [x] **Pre-Deploy Check**: `nix eval .#nixosConfigurations.lab-pi-bk.config.services.minio.enable` → `true`. <!-- id: 11 -->
- [x] **Spec Compliance**: All spec.md acceptance criteria verified — declarative config, no manual commands, MinIO on 9000/9001, data at `/mnt/backups/minio` on ZFS. <!-- id: 12 -->

## Additional Work (not in original tasks)

- [x] **UAS blacklist**: `boot.blacklistedKernelModules = ["uas"]` in `raspberry-pi-4b.nix` — SanDisk Extreme Pro UAS driver crashes on Pi 4B VL805.
- [x] **USB quirks**: `boot.kernelParams = ["usb-storage.quirks=0781:55af:u"]` — forces SanDisk to use BOT protocol instead of UAS.
- [x] **USB 2.0 port**: Drive moved from USB 3.0 (SCSI timeout) to USB 2.0 port — VL805 SuperSpeed link unreliable with this device.
- [x] **ZFS force import**: `-f` flag on `zpool import` — hostid mismatch from hostname change (raspberry-pi4 → lab-pi-bk).
- [x] **Non-blocking boot**: Custom systemd service polls 180s for USB device instead of `boot.zfs.extraPools` which blocks boot.
- [x] **deploy-rs fix**: Renamed deploy packages to avoid shadowing flake output; uses pinned deploy-rs binary.

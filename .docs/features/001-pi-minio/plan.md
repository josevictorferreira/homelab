# Technical Implementation Plan: Pi MinIO Configuration

## 1. Executive Summary
This plan details the configuration of the Raspberry Pi (`lab-pi-bk`) to serve as a MinIO object storage server. We will modify the existing `backup-server` profile to mount the external storage at `/mnt/backups` and configure MinIO to store data there, ensuring a declarative and reproducible NixOS setup.

## 2. Architecture & Design

### 2.1 Component Structure
*   **Profile**: `modules/profiles/backup-server.nix`
    *   Responsibilities:
        *   Import ZFS pool `backup-pool`.
        *   Mount `backup-pool` to `/mnt/backups`.
        *   Configure MinIO service.
        *   (Optional) Update NFS exports to reflect new path.
*   **Service Module**: `modules/services/minio.nix`
    *   Responsibilities: Wrapper for `services.minio` with custom options. (No changes needed, just configuration).

### 2.2 Data Models & State
*   **Storage Path**: `/mnt/backups`
*   **MinIO Data**: `/mnt/backups/minio`
*   **Filesystem**: ZFS (existing `backup-pool`).

### 2.3 Configuration Source of Truth
```nix
# modules/profiles/backup-server.nix
{
  # ...
  config = lib.mkIf cfg.enable {
    # Mount configuration
    fileSystems."/mnt/backups" = {
      device = "backup-pool";
      fsType = "zfs";
    };

    # MinIO Configuration
    services.minioCustom = {
      enable = true;
      dataDir = "/mnt/backups/minio";
      # ...
    };
    
    # ...
  };
}
```

## 3. Implementation Strategy

### Phase 1: Storage Configuration
*   **Goal**: Ensure external drive mounts consistently at `/mnt/backups`.
*   **Key Changes**:
    *   In `modules/profiles/backup-server.nix`:
        *   Keep `boot.zfs.extraPools = [ "backup-pool" ]`.
        *   Add `fileSystems."/mnt/backups"` definition.
        *   Update `services.nfs.server` exports to use `/mnt/backups`.
        *   Update `systemd.tmpfiles.rules` to create `/mnt/backups` and `/mnt/backups/minio`.

### Phase 2: MinIO Service Configuration
*   **Goal**: Run MinIO pointing to the new storage location.
*   **Key Changes**:
    *   In `modules/profiles/backup-server.nix`:
        *   Update `services.minioCustom.dataDir` to `/mnt/backups/minio`.
*   **Verification**:
    *   Build check: `nix flake check`.
    *   (Post-deployment): `curl http://10.10.10.209:9000/minio/health/live`.

## 4. Risk Assessment & Mitigation
*   **Data Availability**: Moving mount point from `/backups` to `/mnt/backups` might break existing paths if manually referenced.
    *   *Mitigation*: Update NFS exports and MinIO config simultaneously.
*   **ZFS Mount**: If `backup-pool` has `mountpoint` property set to `/backups`, `fileSystems` definition might conflict or require `legacy` mountpoint.
    *   *Mitigation*: We will assume standard ZFS behavior. If conflict arises, we may need to set `boot.zfs.extraPools` only and rely on ZFS properties, OR set `zfs set mountpoint=legacy backup-pool` (manual step, avoided).
    *   *Refined Strategy*: Since "No manual commands allowed", we will rely on NixOS `fileSystems` to manage the mount. NixOS handles ZFS mounts well. If the pool is imported, NixOS tries to mount it.
*   **Existing Data**: We assume the pool exists. We are not formatting drives.

## 5. Verification Plan
*   **Syntax Check**: `nix insta-check` (or `make check`).
*   **Configuration Review**: Verify `nodes.nix` assigns `backup-server` role to `lab-pi-bk`.

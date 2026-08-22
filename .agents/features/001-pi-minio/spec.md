# Product Requirements: Pi MinIO Configuration

## 1. Overview
Configure the Raspberry Pi (`lab-pi-bk`) to serve as an off-cluster backup hub using MinIO. This is a foundational step for the broader backup strategy.

## 2. Requirements
- **Target Node**: `lab-pi-bk` (Raspberry Pi 4B).
- **Storage**:
  - Mount the external HDD to `/mnt/backups`.
  - Ensure the configuration is declarative and reproducible.
- **Service**:
  - Enable MinIO: `services.minio.enable = true`.
  - Protocol: HTTP only (no TLS for now).
  - Data Directory: `/mnt/backups/minio`.
- **Constraint**:
  - Do NOT implement full backup jobs yet.
  - No manual commands in the final install.
  - "Don't do anything more than the Pi MinIO Configuration".

## 3. Existing Implementation (Reference)
- Current profile: `modules/profiles/backup-server.nix`.
- Uses ZFS pool `backup-pool`.
- Currently mounts to `/backups` (implied by ZFS or defaults).
- Currently exports NFS (to be updated/maintained for consistency or ignored if out of scope, but path must be correct).

## 4. Acceptance Criteria
- `lab-pi-bk` builds successfully.
- External drive mounts at `/mnt/backups`.
- MinIO is running and accessible on port 9000/9001.
- MinIO writes data to `/mnt/backups/minio`.

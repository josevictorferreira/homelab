# Proton Drive Shared Subfolders Backup

## Implementation Status

**Wave 1 (Foundation)**: ✅ Complete
- T1: Validated source paths (/shared/notetaking, /shared/images, /shared/backups exist)
- T2: MinIO bucket `homelab-backup-shared` + credentials created
- T3: Backup artifact format (tar.zst + sha256 + manifest.json)
- T4: Secret wiring for S3 credentials
- T5: CronJob `shared-subfolders-backup` created (daily at 01:00)

**Wave 2 (Monitoring)**: ✅ Complete
- T7: Grafana alerts added (job failure >0 in 6h, staleness >26h)

**Wave 3 (Proton Drive)**: 🔄 In Progress
- T10: Proton Drive client + auth bootstrap
- T11: Proton sync workload (MinIO → Proton)
- T12: Proton sync alerts

## Key Patterns Discovered

### Backup Artifact Format
- Archive: `shared-YYYY-MM-DD.tar.zst`
- Checksum: `shared-YYYY-MM-DD.tar.zst.sha256`
- Manifest: `shared-YYYY-MM-DD.manifest.json`
- Atomic upload: `.tmp` → final rename

### Secret Management
- SOPS secrets in `secrets/k8s-secrets.enc.yaml`
- Kubenix secret configs in `modules/kubenix/apps/*-credentials.enc.nix`
- Keys follow pattern: `minio_${service}_${access_key|secret_key}`

### MinIO Bootstrap Pattern (Pi)
- `modules/profiles/backup-server.nix` manages MinIO users/buckets
- Add service name to `SERVICES` array
- Bucket auto-created as `homelab-backup-${service}`

### Proton Drive Sync
- Image: `ghcr.io/damianb-bitflipper/proton-drive-sync:latest`
- Requires `KEYRING_PASSWORD` env var for encryption
- Volumes: `/config` (credentials), `/state` (sync state)
- Auth: Interactive `proton-drive-sync auth` command
- Sync: `proton-drive-sync sync` command

## Known Issues

### T1 Path Correction
- Plan specified `/shared/backup` but actual path is `/shared/backups` (with 's')
- Updated implementation to use `backups`

### Cross-Compilation
- `make manifests` requires x86_64-linux
- Cannot run directly on darwin (aarch64-darwin)
- Nix syntax validated with `nix-instantiate --parse`

## Files Created/Modified

### Wave 1
- `modules/kubenix/apps/shared-subfolders-backup.nix` (new)
- `modules/kubenix/apps/shared-subfolders-backup-s3-credentials.enc.nix` (new)
- `secrets/k8s-secrets.enc.yaml` (modified - added minio_shared_backup_*)

### Wave 2
- `modules/kubenix/monitoring/grafana-backup-alerts.nix` (modified)
- `modules/profiles/backup-server.nix` (modified - added 'shared' to SERVICES)

### Wave 3 (Pending)
- `modules/kubenix/apps/shared-subfolders-proton-sync.nix` (pending)
- `modules/kubenix/apps/shared-subfolders-proton-config.enc.nix` (pending)
- `secrets/k8s-secrets.enc.yaml` (pending - add proton credentials)

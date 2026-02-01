# Implementation Tasks: Pi MinIO Configuration

## Phase 1: Storage Configuration
Goal: Ensure external drive mounts consistently at `/mnt/backups` and NFS exports are updated.

- [ ] **Context Gather**: Read `modules/profiles/backup-server.nix` to understand current filesystem and NFS config. <!-- id: 0 -->
- [ ] **Filesystem Definition**: In `modules/profiles/backup-server.nix`, add `fileSystems."/mnt/backups"` configuration using `backup-pool`. <!-- id: 1 -->
- [ ] **Update NFS Exports**: In `modules/profiles/backup-server.nix`, update `services.nfs.server.exports` to point to `/mnt/backups` (if applicable). <!-- id: 2 -->
- [ ] **Tmpfiles Rules**: Add `systemd.tmpfiles.rules` to create `/mnt/backups/minio` directory with correct permissions. <!-- id: 3 -->
- [ ] **Lint Check**: Run `make lint` or `nixfmt` to ensure no syntax errors. <!-- id: 4 -->
- [ ] **Build Verification**: Run `nix flake check` (or `make check`) to verify configuration validity. <!-- id: 5 -->

## Phase 2: MinIO Service Configuration
Goal: Configure MinIO to use the new storage location.

- [ ] **Update Data Dir**: In `modules/profiles/backup-server.nix`, update `services.minioCustom.dataDir` to `/mnt/backups/minio`. <!-- id: 6 -->
- [ ] **Ensure HTTP**: Verify `services.minioCustom` is configured for HTTP (no TLS required yet). <!-- id: 7 -->
- [ ] **Lint Check**: Run `make lint` to ensure style consistency. <!-- id: 8 -->
- [ ] **Final Build Verification**: Run `nix flake check` to ensure the entire system configuration is valid. <!-- id: 9 -->

## Phase 3: Final Verification
Goal: Confirm the setup matches the requirements.

- [ ] **Review**: Verify `nodes.nix` still assigns `backup-server` role to `lab-pi-bk`. <!-- id: 10 -->
- [ ] **Pre-Deploy Check**: Run `nix eval .#nixosConfigurations.lab-pi-bk.config.services.minio.enable` to confirm it evaluates to true. <!-- id: 11 -->
- [ ] **Spec Compliance**: Verify against `spec.md` requirements (declarative, reproducible, no manual commands). <!-- id: 12 -->

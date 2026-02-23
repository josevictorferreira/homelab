# Custom Images Migration Todo List

This document tracks all custom-built container images used in the homelab that should be migrated into this repository for unified management.

## Overview

**Source Registry:** `ghcr.io/josevictorferreira`  
**Target:** Build and manage images directly in this repository using Nix  
**Total Images:** 11 unique images across 14 service definitions

---

## Active Images (In Use)

### 1. `backup-toolbox`
- **Current Image:** `ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb`
- **Used By:**
  - `modules/kubenix/backup/postgres-backup.nix`
  - `modules/kubenix/backup/postgres-restore-drill.nix` (as toolbox)
  - `modules/kubenix/backup/shared-subfolders-backup.nix`
  - `modules/kubenix/backup/shared-subfolders-proton-sync.nix`
  - `modules/kubenix/backup/shared-subfolders-restore-drill.nix` (as toolbox)
  - `modules/kubenix/backup/etcd-snapshot-offload.nix`
- **Purpose:** General-purpose backup utilities (rclone, mc, zstd, psql, etc.)
- **Migration Priority:** HIGH - Core infrastructure component
- **Notes:** Multi-purpose image used across 6 different CronJobs

---

### 2. `postgresql-vchord-bitnami`
- **Current Image:** `ghcr.io/josevictorferreira/postgresql-vchord-bitnami:38c40fefe0c58cff6622de77f787634320e1ae5e`
- **Used By:**
  - `modules/kubenix/apps/postgresql-18.nix`
  - `modules/kubenix/backup/postgres-restore-drill.nix`
- **Purpose:** Bitnami PostgreSQL 16 with pgvecto.rs (vchord.so) extension for vector similarity search
- **Migration Priority:** HIGH - Database infrastructure
- **Notes:** Uses commit hash as tag. pgvecto.rs enables AI/ML workloads (OpenWebUI, Immich, etc.)

---

### 3. `valoris-frontend`
- **Current Image:** `ghcr.io/josevictorferreira/valoris-frontend:latest`
- **Used By:** `modules/kubenix/apps/valoris.nix`
- **Purpose:** Frontend (nginx) for Valoris application
- **Migration Priority:** MEDIUM - Application service
- **Notes:** Uses `latest` tag, needs version pinning

---

### 4. `valoris-backend`
- **Current Image:** `ghcr.io/josevictorferreira/valoris-backend:latest`
- **Used By:**
  - `modules/kubenix/apps/valoris.nix` (backend + worker)
- **Purpose:** Rails backend API and background job worker for Valoris
- **Migration Priority:** MEDIUM - Application service
- **Notes:** Same image used for both web and worker containers; uses `latest` tag

---

### 5. `openclaw-nix`
- **Current Image:** `ghcr.io/josevictorferreira/openclaw-nix:latest`
- **Used By:** `modules/kubenix/apps/openclaw-nix.nix`
- **Purpose:** AI assistant platform (Matrix/WhatsApp gateway with tool calling)
- **Migration Priority:** MEDIUM - AI/Service platform
- **Notes:** Complex configuration with plugins for Matrix, WhatsApp; uses `latest` tag

---

## Disabled Images (Prefixed with `_`)

These images are not currently deployed but exist in the codebase:

### 6. `youtube-transcriber`
- **Current Image:** `ghcr.io/josevictorferreira/youtube-transcriber:0.0.1@sha256:13510480faf6e70c5d02b2623cf4192c03f52f246d9d00415e4a1a75326c95bd`
- **File:** `modules/kubenix/apps/_youtube-transcriber.nix` (disabled)
- **Purpose:** YouTube video transcription service
- **Migration Priority:** LOW - Disabled service
- **Notes:** Properly pinned with digest; v0.0.1

---

### 7. `alarm-server`
- **Current Image:** `ghcr.io/josevictorferreira/alarm-server:v0.2.3@sha256:317714c3c6d0939cc89aef10b00cee5dde4dd455b820c98d6cc9dbddc1552626`
- **File:** `modules/kubenix/apps/_alarm-server.nix` (disabled)
- **Purpose:** Alarm/notification server
- **Migration Priority:** LOW - Disabled service
- **Notes:** Properly pinned with digest; v0.2.3

---

### 8. `libebooker`
- **Current Image:** `ghcr.io/josevictorferreira/libebooker:latest`
- **File:** `modules/kubenix/apps/_libebooker.nix` (disabled)
- **Purpose:** E-book management service
- **Migration Priority:** LOW - Disabled service
- **Notes:** Uses `latest` tag

---

### 9. `openrouter-proxy`
- **Current Image:** `ghcr.io/josevictorferreira/openrouter-proxy:v0.0.5`
- **File:** `modules/kubenix/apps/_openrouter-proxy.nix` (disabled)
- **Purpose:** Proxy service for OpenRouter API
- **Migration Priority:** LOW - Disabled service
- **Notes:** v0.0.5

---

### 10. `mcpo`
- **Current Image:** `ghcr.io/josevictorferreira/mcpo:latest@sha256:87bf1da9ed289777a08e4e5816cc9f8a9df5cee259842ac5ff3a223f0256ecc2`
- **File:** `modules/kubenix/apps/_mcpo.nix` (disabled)
- **Purpose:** MCP (Model Context Protocol) orchestrator
- **Migration Priority:** LOW - Disabled service
- **Notes:** Uses `latest` tag but has digest

---

### 11. `ollama`
- **Current Image:** `ghcr.io/josevictorferreira/ollama:0.12.6-1-g7f551c4-dirty-rocm@sha256:68ca90ec1f47a047084a0e6ab355dd5598bcd8644417f0a6633f2c7298c7313f`
- **File:** `modules/kubenix/apps/_ollama.nix` (disabled)
- **Purpose:** Ollama LLM runtime with AMD ROCm GPU support
- **Migration Priority:** LOW - Disabled service
- **Notes:** Custom build for AMD GPU support; ROCm stack for Ryzen PRO 5650U

---

### 12. `postgresql-vchord-bitnami` (Legacy Version)
- **Current Image:** `ghcr.io/josevictorferreira/postgresql-vchord-bitnami:54c9cd376be1eb5a2b3baf4df0f4dc86c472325c`
- **File:** `modules/kubenix/apps/_postgresql.nix` (disabled)
- **Purpose:** Legacy PostgreSQL with pgvecto.rs (older commit)
- **Migration Priority:** LOW - Disabled service (replaced by postgresql-18)
- **Notes:** Older commit hash; service disabled in favor of postgresql-18

---

## Migration Checklist

### Phase 1: Infrastructure Images (HIGH Priority)
- [ ] Create Nix derivation for `backup-toolbox`
  - [ ] Include: rclone, minio-client (mc), zstd, postgresql-client, jq, curl, bash
  - [ ] Multi-arch support (amd64 + arm64 for Pi)
- [ ] Create Nix derivation for `postgresql-vchord-bitnami`
  - [ ] Extend bitnami/postgresql base image
  - [ ] Add pgvecto.rs (vchord.so) extension build
  - [ ] Handle shared_preload_libraries configuration

### Phase 2: Application Images (MEDIUM Priority)
- [ ] Create Nix derivation for `valoris-frontend`
  - [ ] Static nginx build
- [ ] Create Nix derivation for `valoris-backend`
  - [ ] Rails application container
  - [ ] Assets precompilation
- [ ] Create Nix derivation for `openclaw-nix`
  - [ ] Node.js-based application
  - [ ] Include Matrix and WhatsApp plugins dependencies

### Phase 3: Disabled Services (LOW Priority)
- [ ] Evaluate which disabled services to migrate vs. deprecate
- [ ] Create derivations for actively-used disabled images
- [ ] Document deprecated images

### Phase 4: CI/CD Integration
- [ ] Set up GitHub Actions workflow for automatic image builds
- [ ] Integrate with existing `make manifests` pipeline
- [ ] Version pinning strategy (digest-based)
- [ ] Multi-architecture builds (amd64, arm64)

---

## Migration Benefits

1. **Single Source of Truth:** All infrastructure code in one repo
2. **Version Pinning:** Nix provides reproducible builds with exact dependency versions
3. **Security:** No reliance on external GHCR builds; build from source
4. **Offline Capability:** Can rebuild images without external registry access
5. **Cost:** No GHCR storage costs for private images
6. **Transparency:** Full visibility into image contents and build process

---

## Technical Notes

### Build Strategy
- Use `nixpkgs.dockerTools.buildImage` or `buildLayeredImage` for OCI images
- Leverage `nix2container` for efficient layer caching
- Store image definitions in `containers/` or `images/` directory

### Registry Strategy
- Continue pushing to `ghcr.io/josevictorferreira` for runtime use
- Or use internal registry (Harbor/Distribution) if deployed
- Tag with Git commit SHA for traceability

### Version Updates
- Update image tags in kubenix modules after each build
- Use `make manifests` to regenerate with new digests
- Keep changelog of image updates

---

## References

- Files to update after migration:
  - `modules/kubenix/backup/*.nix`
  - `modules/kubenix/apps/postgresql-18.nix`
  - `modules/kubenix/apps/valoris.nix`
  - `modules/kubenix/apps/openclaw-nix.nix`
  - `modules/kubenix/apps/_*.nix` (if re-enabling)

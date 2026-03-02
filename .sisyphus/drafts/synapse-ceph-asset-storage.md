# Draft: Synapse asset storage on Ceph bucket (Ceph RGW / S3)

## Goal (from user)
- Start using a Ceph-backed "object store bucket" as the main asset/media storage for Matrix Synapse.

## Terminology to clarify
- "CephFS object store bucket" is ambiguous:
  - **CephFS** = shared filesystem (mount via PVC)
  - **Object store bucket** = Ceph RGW (S3-compatible) bucket
- Likely intent: **Ceph RGW S3 bucket** for Synapse media (and/or matrix-media-repo).

## Key design options (pending)
1. **Synapse + S3 media storage provider** (plugin/module) → store media in S3 bucket.
2. **matrix-media-repo + S3 backend** (recommended for multi-synapse) → Synapse delegates media to MMR.
3. **CephFS PVC mounted as Synapse media dir** (simplest, not a bucket) → shared filesystem.

## Decisions (confirmed)
- Target approach: **Synapse direct to S3** (via storage provider module).
- Synapse topology: **single replica only**.
- Migration tolerance: **downtime OK**.
- Credentials: **generated creds** (ObjectBucketClaim Secret).
- Media scope: **store local + remote**.
- S3 key prefix: **YES** (e.g., `synapse/`).
- RGW endpoint_url: **in-cluster HTTP service** (cluster-local DNS, no ingress).
- Bucket provisioning: **new ObjectBucketClaim** (in apps ns).
- Migration execution: **manual** (`kubectl exec` / one-off pod) with a runbook (not a GitOps Job).

## Repo findings (confirmed)
- Synapse deployed via Helm: `modules/kubenix/apps/matrix.nix`
  - Chart: ananace/matrix-synapse `3.12.19`
  - Image: `ghcr.io/element-hq/synapse:v1.146.0`
  - Ingress: `matrix.josevictor.me` (cilium + cert-manager, wildcard-tls)
  - Current persistence: PVC `rook-ceph-block`, RWO, `20Gi`, `Recreate` strategy
- Ceph RGW object store already enabled: `modules/kubenix/storage/rook-ceph-cluster.nix`
  - ObjectStore name: `ceph-objectstore`
  - StorageClass: `rook-ceph-objectstore`
  - Ingress host: `objectstore.${homelab.domain}` (wildcard-tls)
  - Helper endpoint for in-cluster clients: `kubenix.lib.objectStoreEndpoint` in `modules/kubenix/_lib/default.nix`
- Bucket provisioning pattern used by other apps: ObjectBucketClaim (`objectbucket.io/v1alpha1`) + secret in-app namespace
  - Examples: `modules/kubenix/apps/open-webui.nix`, `imgproxy.nix`, `linkwarden.nix`
- CephObjectStoreUser pattern exists too: `modules/kubenix/apps/s3-credentials.enc.nix` creates `cephobjectstoreuser."s3-user"`.

## Scope assumptions (not yet confirmed)
- Assets = Synapse media repository (uploads, thumbnails, remote media cache).
- Not touching secrets outside SOPS/kubenix patterns.
- No destructive Ceph actions (no finalizers removal; no CR deletion).

## Open questions
- Are you running **Synapse in this k3s/kubenix homelab**? (or bare metal/VM)
- Do you already run **matrix-media-repo**? If yes, version + current backend.
- Do you need **multiple Synapse replicas** (HA) sharing media?
- Current media storage location + size (PVC type, CephFS/RBD/local path) and migration tolerance (downtime ok?).
- Do you already have **Rook-Ceph RGW ObjectStore** deployed? Any existing buckets/credentials patterns?

## Open questions (new)
- Downtime window: how long is acceptable for the migration (minutes/hours)?
- Failure mode: if RGW/S3 is unavailable, should Synapse **fail uploads hard** (no fallback) or should we plan a **local fallback** path?

## Implementation direction (proposed)
- Use **Ceph RGW bucket** (via ObjectBucketClaim) for Synapse media.
- Install `synapse-s3-storage-provider` into the Synapse runtime (initContainer pip install into shared volume, or build custom image).
- Configure Synapse `media_storage_providers:` to write media to S3 (RGW endpoint via `kubenix.lib.objectStoreEndpoint`).
- Migrate existing local media to S3 with `s3_media_upload` during downtime.

## Research findings (authoritative)
- Synapse has **no native S3 media backend**.
  - Requires external module: `matrix-org/synapse-s3-storage-provider`.
  - `homeserver.yaml` key: `media_storage_providers:` with module `s3_storage_provider.S3StorageProviderBackend`.
  - Main toggles: `store_local`, `store_remote`, `store_synchronous`.
  - S3 config: `bucket`, `region_name`, `endpoint_url`, `access_key_id`, `secret_access_key`, optional `prefix`, `threadpool_size`.
  - Migration helper script exists: `s3_media_upload` (update/upload, optional `--delete`).

## Risks / gotchas to plan around
- Need a way to **ship the Python module** into the Synapse container (custom image vs initContainer pip install to shared volume).
- For S3-compatible endpoints, may need checksum compatibility toggles (MinIO/RGW quirks).
- `prefix` choice is sticky (changing later risks “missing media” unless migrated).

## Non-goals (likely)
- Moving Synapse DB (Postgres) to Ceph.
- Storing signing keys/secrets in object storage.

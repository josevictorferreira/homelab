# Draft: Synapse media storage providers

## Goal
- Enable reliable media uploads (images) to Synapse for:
  - humans (Matrix clients)
  - OpenClaw bot

## Symptom / Evidence
- Bot log (PT-BR):
  - `✅ Conectar ao Synapse interno (http://synapse-matrix-synapse:8008)`
  - `✅ Fazer upload da imagem e obter o MXC URI`
  - `❌ O arquivo foi removido antes de eu enviar a mensagem`

## Working hypotheses (to validate)
- Synapse media storage is ephemeral (emptyDir/tmp) or pod restarts → uploaded media disappears quickly.
- Synapse media retention/cleanup job too aggressive (unlikely to be seconds, but check).
- Bot/library workflow reads the file again (thumbnail/metadata) after upload → bot deletes temp file too early (bot-side, not Synapse-side).

## Requirements (unconfirmed)
- Want choice of storage backends (at least PVC filesystem; optionally S3-compatible like MinIO/Ceph RGW).
- Want persistence + durability (no media loss on pod restart).

## Requirements (confirmed)
- Target backend: S3 bucket on Ceph Object Store (RGW). User wants to mirror existing cluster patterns (e.g., linkwarden/valoris).
- Bot/Synapse issue triage: MXC download test not yet done.

## Scope boundaries (TBD)
- INCLUDE: Synapse media repo storage config + K8s persistence/secrets wiring + verification steps.
- EXCLUDE (unless requested): migrating historic media between backends; changing bot code.

## Open questions
- Synapse deployment method in this repo (kubenix module path)?
- Current `media_store_path` and whether it’s on a PVC?
- Synapse version and whether `media_storage_providers` modules are available.
- Any evidence of Synapse pod restarts around upload time?
- Bot library / code path used for upload+send (does it generate thumbnails?)

## Repo findings (confirmed)
- Synapse is deployed via Helm release in `modules/kubenix/apps/matrix.nix`.
  - Chart: `matrix-synapse` (Element) v3.12.19
  - Image: `ghcr.io/element-hq/synapse:v1.146.0`
  - Persistence: 20Gi PVC (storageClass `rook-ceph-block`) mounted at chart data dir (likely `/data`).
- OpenClaw points at internal service URL: `http://synapse-matrix-synapse:8008` (see `modules/kubenix/apps/openclaw.enc.nix`).

## External research findings (Synapse capabilities)
- Synapse does **not** include built-in S3 media storage.
- Remote/backing stores use `media_storage_providers`:
  - Built-in provider: filesystem
  - S3 requires external python module: `synapse-s3-storage-provider` (matrix-org)
- Even with remote backing store, Synapse still uses local filesystem cache → PVC still needed.
- Version note: synapse-s3-storage-provider must be compatible with Synapse (>=1.6.0 required for Synapse >=1.140 per upstream notes).

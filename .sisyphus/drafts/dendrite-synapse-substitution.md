# Draft: Synapse + Dendrite parallel (matrixx)

## Requirements (confirmed)
- Keep current Synapse running on `matrix.josevictor.me`.
- Deploy Dendrite in parallel on `matrixx.josevictor.me` for testing.
- No Synapse→Dendrite migration now.

## Requirements (user answers)
- Synapse stays authoritative; no cutover.
- Dendrite host: `matrixx.josevictor.me`.
- Dendrite `server_name`: `josevictor.me` (same as Synapse).
- `/.well-known` stays pointing to Synapse only.
- Dendrite registration: disabled.
- LAN-only exposure (no Cloudflare changes).
- Create 1 dedicated Dendrite test account for Element Web login.

## Confirmations (ready to execute)
- Reserve internal DNS/LB map entry: `matrixx = 10.10.10.142` in `config/kubernetes.nix`.
- Test MXID to create: `@dendrite-test:josevictor.me`.

## Scope Boundaries
- INCLUDE: Dendrite parallel deploy, isolated DB+PVC+ingress on matrixx.
- EXCLUDE: modifying Synapse/bridges, migrating rooms/history/media, cutover, federation.

## Technical Decisions
- Dendrite is **non-federating** (mandatory guardrail for shared `server_name`).
- Bridges remain pointed at Synapse (no Dendrite appservice work).
- Dendrite user creation via kubernetes Job running Dendrite CLI (idempotent).

## Research Findings
- Current stack (repo):
  - Synapse helm release: `modules/kubenix/apps/matrix.nix` + secrets `modules/kubenix/apps/matrix-config.enc.nix`.
  - Synapse image pinned: `ghcr.io/element-hq/synapse:v1.146.0`.
  - Synapse uses external PostgreSQL (`modules/kubenix/apps/postgresql-18.nix`) + external Redis; ingress `matrix.josevictor.me`.
  - Synapse media uses S3 provider with bucket `matrix-synapse-media` (object store creds from SOPS secrets).
  - Bridges present: mautrix-whatsapp, mautrix-discord, mautrix-slack (Nix modules + generated manifests).
- DNS mapping mechanism: Blocky maps every `homelab.kubernetes.loadBalancer.services` entry to `${name}.${homelab.domain} -> homelab.kubernetes.loadBalancer.address` (`modules/kubenix/apps/blocky-config.enc.nix`).
- Ingress+TLS patterns: `modules/kubenix/apps/matrix.nix` and `modules/kubenix/apps/keycloak.nix`.
- Raw resources pattern (Deployment+Service): `modules/kubenix/apps/flaresolverr.nix`.
- Postgres DB bootstrap: `config/kubernetes.nix` list consumed by `modules/kubenix/apps/postgresql-18.nix` Job.

## Open Questions
- None blocking planning (remaining unknowns are handled as explicit executor discovery tasks: exact Dendrite CLI flags + account creation command).

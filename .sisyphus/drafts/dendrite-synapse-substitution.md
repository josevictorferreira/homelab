# Draft: Synapse → Dendrite substitution (Matrix homeserver)

## Requirements (confirmed)
- Read Dendrite repo + docs; assess if it can replace current Synapse.
- If yes: verify current bridges compatibility with Dendrite.
- Assess if Matrix data can be migrated seamlessly from current Synapse.

## Requirements (user answers)
- “Seamless” requirement changed: **do NOT need to preserve devices/E2EE continuity**.
- Downtime window acceptable: **1-4 hours**.
- Must-have: **appservice bridges** (mautrix-whatsapp/discord/slack).

## Additional constraints (user answers)
- Must keep same `server_name` / domain: **matrix.josevictor.me** / MXIDs on `josevictor.me`.
- Must preserve: **rooms + full history + media**.
- Bridge rooms: **unencrypted OK**.
- Clients day-1: **Element Web + Element X**.
- Safety: **no rollback target AND no snapshot/restore path**.

## Technical Decisions
- (pending) Allowed fallback if seamless migration impossible.
- (pending) Cutover approach: keep same `server_name` (matrix.josevictor.me) vs new server + side-by-side.
- (pending) Bridge encryption requirement (bridged rooms encrypted or not).

## Research Findings
- Current stack (repo):
  - Synapse helm release: `modules/kubenix/apps/matrix.nix` + secrets `modules/kubenix/apps/matrix-config.enc.nix`.
  - Synapse image pinned: `ghcr.io/element-hq/synapse:v1.146.0`.
  - Synapse uses external PostgreSQL (`modules/kubenix/apps/postgresql-18.nix`) + external Redis; ingress `matrix.josevictor.me`.
  - Synapse media uses S3 provider with bucket `matrix-synapse-media` (object store creds from SOPS secrets).
  - Bridges present: mautrix-whatsapp, mautrix-discord, mautrix-slack (Nix modules + generated manifests).
- Dendrite docs (key gaps relevant here):
  - Missing MSC4186 sliding-sync, MSC3861 OIDC, limited admin API.
  - Appservice-related open issues: MSC2409 ephemeral events to appservices; MSC3202 E2EE appservice support.
- Feasibility verdict (oracle): **Seamless Synapse→Dendrite migration preserving E2EE/devices not feasible**; recommend side-by-side or new-server migration, keep Synapse as legacy archive.

## Open Questions
- If seamless is impossible: do you still want Dendrite (with compromises), or stop and stay on Synapse?
- Must keep same `server_name` (matrix.josevictor.me), or acceptable to introduce a new homeserver name and run side-by-side?
- Are bridged rooms required to be E2EE?

## Blocking conflicts discovered
- Element X typically depends on sliding-sync; Dendrite docs state **MSC4186 sliding-sync not implemented** → likely client breakage unless Element X has fallback.
- “No restore path” is incompatible with any DB/media migration attempt; must allow at least backups/snapshots or accept non-zero data-loss risk.

## Scope Boundaries
- INCLUDE: feasibility + gaps, bridge compatibility, migration options + risks.
- EXCLUDE: executing the migration (implementation deferred to /start-work).

# Draft: Matrix server + bridges (Slack/Discord/WhatsApp)

## Original request
- Choose a Matrix server (self-host e.g. Synapse, or hosted)
- Set up bridges:
  - Slack → Matrix (slack bridge)
  - Discord → Matrix (Discord bridge)
  - WhatsApp → Matrix (mautrix-whatsapp or similar)

## Requirements (confirmed)
- Kubernetes homelab cluster (kubenix + Flux GitOps)
- Matrix homeserver + bridging services deployed/managed via repo (no manual kubectl apply for persistence)

## Decisions (confirmed)
- Homeserver: Synapse (self-host)
- Federation: OFF (private-only)
- Bridge mode: relay-bot only
- Client access: LAN-only
- Web client: none deployed (use existing clients)
- Bridge impl preference: default to mautrix family when available
- Synapse server_name: matrix.josevictor.me (public domain, but service LAN-only)
- TLS: reuse existing wildcard cert via K8s secret `wildcard-tls`
- DNS: matrix.josevictor.me should resolve (LAN) to Cilium ingress shared LB IP 10.10.10.110 (from config/kubernetes.nix)
- Traffic: Synapse behind Ingress on shared Cilium ingress LB IP (no dedicated LB service IP)
- Internal DNS mgmt: manage split-horizon record via in-cluster Blocky config
- Namespace: `matrix`
- TURN: out of scope
- Synapse accounts: invite-only; bootstrap 1 admin
- Datastores: reuse existing shared Postgres + Redis (separate DB/users per component)
- Bridged rooms: force unencrypted (no E2EE) for bridged rooms
- Slack bridge: `mautrix-slack` using “App login” (outbound-only; no inbound callbacks; not Socket Mode)
- Discord bridge: `mautrix-discord` LAN-only (accept avatar/proxy limitations if any)
- WhatsApp bridge: `mautrix-whatsapp`; DoD = deployed + waiting for QR pairing (user scans later)
- Bridge creds: user will create Slack/Discord apps + provide tokens via SOPS secrets
- Postgres DB names to auto-create: `synapse`, `mautrix_slack`, `mautrix_discord`, `mautrix_whatsapp`
- Reserved LB IP key for internal DNS + service annotations: `loadBalancer.services.matrix = 10.10.10.138`
- Synapse media PVC: 20Gi
- Matrix IDs: `@user:matrix.josevictor.me`
  - Note: Blocky uses the *key* (`matrix`) to create `matrix.josevictor.me → 10.10.10.110` record; value `10.10.10.138` is just reservation for any future LoadBalancer Service annotations.

## Definition of done (confirmed)
- Bridges: “infra ready” only (pods/services/ingress/secrets wiring + basic health); no requirement to prove Slack/Discord message flow; WhatsApp OK to be waiting for QR scan

## Research findings (external)
- Bridges: use mautrix family
  - mautrix-slack: **does NOT support Slack Socket Mode**; “App login” w/ Slack app tokens works without inbound callbacks (outbound-only)
  - mautrix-discord: docs mention `public_address` used for avatar proxy; may imply some inbound reachability for best UX
  - mautrix-whatsapp: requires one-time QR pairing; relay mode => no E2EE
  - Relay-bot mode: generally incompatible w/ E2EE → keep bridged rooms unencrypted
  - Docs: https://docs.mau.fi/bridges/go/{slack,discord,whatsapp}/ ; Synapse appservices: https://element-hq.github.io/synapse/latest/usage/configuration/application_services.html

## Pending repo changes implied by decisions
- `config/kubernetes.nix`:
  - Add namespace entry: `matrix = "matrix"` so cert-manager creates `wildcard-tls` secret there
  - Reserve service key for Blocky internal DNS generation: `loadBalancer.services.matrix = <free IP>` (value mostly serves as reservation / annotations)
    - Candidate free IPs (based on current list): `10.10.10.104`, `10.10.10.124`, `10.10.10.125`, `10.10.10.137`, `10.10.10.138`
  - Add Postgres DB names to `databases.postgres` for Synapse + bridges

## Infra facts (repo)
- `config/kubernetes.nix`:
  - LB range: 10.10.10.100-199
  - Cilium ingress shared LB IP: `homelab.kubernetes.loadBalancer.address = 10.10.10.110`
  - Per-service reserved LB IPs in `homelab.kubernetes.loadBalancer.services.*`
- `modules/kubenix/system/cilium.nix`: Cilium ingress controller uses the shared LB IP above

## Scope boundaries (TBD)
- INCLUDE: deploy homeserver, DB/cache deps, ingress/TLS, appservice registration, bridge deployments, secrets wiring (SOPS/vals), basic health verification
- EXCLUDE (maybe): user account provisioning, Element/clients, E2EE policy, manual pairing steps (WhatsApp QR, Slack/Discord bot installation) — needs decision

## Research findings (repo conventions)
- Kubenix apps live in `modules/kubenix/apps/`
- Shared deps already exist:
  - Postgres: `modules/kubenix/apps/postgresql-18.nix` + secrets in `modules/kubenix/apps/postgresql-auth.enc.nix`
  - Redis: `modules/kubenix/apps/redis.nix` + secrets in `modules/kubenix/apps/redis-auth.enc.nix`
- “External DB” app patterns to copy: `modules/kubenix/apps/n8n.nix`, `modules/kubenix/apps/linkwarden.nix`
- Ingress + secrets helpers: `modules/kubenix/_lib/default.nix` (ingressFor/ingressDomainFor*, secretsFor/secretsInlineFor)
- K8s secrets source of truth: `secrets/k8s-secrets.enc.yaml`
- Pipeline: `make manifests` (gmanifests → vmanifests(vals inject) → umanifests → emanifests(SOPS))
- Gotcha: flake uses git state; new files must be staged before `make check`

## Technical decisions (open)
- Backing services: reuse shared Postgres + (maybe) shared Redis
- Ingress: domain names, TLS, well-known, federation on/off
- Storage: PVC classes/sizes (rook-ceph-block?)
- Bridges: matrix-appservice-slack vs mautrix-slack; matrix-appservice-discord vs mautrix-discord; mautrix-whatsapp
- E2EE posture for bridged rooms

## Verification strategy (open)
- Agent-executable verification only: what “done” means without manual QR/oauth steps

## Secrets needed (expected)
- Matrix server signing key, registration secret, admin credentials bootstrap
- Postgres creds
- Bridge appservice tokens/registration YAML
- Slack/Discord bot creds; WhatsApp session/phone pairing artifacts

## Open questions (remaining)
- Media retention expectations (rough): small/medium/large; (only affects sizing/monitoring, not core architecture)

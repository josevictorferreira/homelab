# Matrix Bridges - Learnings

## Notepad Structure
- learnings.md - Conventions, patterns discovered
- decisions.md - Architectural choices made
- issues.md - Problems encountered and solutions
- problems.md - Unresolved blockers

## Task 6: Bridge Module Creation (2026-02-05)

### Mautrix Bridge Module Pattern
- Use raw kubernetes.resources.deployments (not Helm) for bridges
- Each bridge needs: Deployment, Service, and optionally PVC
- Registration YAML already created in matrix-config.enc.nix (Task 5)
- Config secrets need to be created separately (mautrix-*-config)
- Environment secrets for tokens (mautrix-*-env)

### Bridge Configuration Details
**All bridges:**
- Namespace: homelab.kubernetes.namespaces.matrix
- Synapse URL: http://matrix.matrix.svc.cluster.local:8008
- PostgreSQL: postgresql-18-hl with shared postgres user
- Command: --no-update flag to prevent automatic updates
- Registration mount: /data/registration.yaml (read-only)
- Config mount: /data/config.yaml (read-only)

**Slack (mautrix-slack):**
- Image: ghcr.io/mautrix/slack:v0.1.3
- Port: 29328
- Replicas: 0 (waiting for Slack app/bot tokens)
- Storage: emptyDir (no persistent data needed)
- Database: mautrix_slack

**Discord (mautrix-discord):**
- Image: ghcr.io/mautrix/discord:v0.6.0
- Port: 29334
- Replicas: 0 (waiting for Discord bot token)
- Storage: emptyDir (no persistent data needed)
- Database: mautrix_discord

**WhatsApp (mautrix-whatsapp):**
- Image: ghcr.io/mautrix/whatsapp:v0.11.1
- Port: 29318
- Replicas: 1 (running, waiting for QR scan)
- Storage: 1Gi PVC (rook-ceph-block) for session data
- Database: mautrix_whatsapp

### Secret References
- PostgreSQL password: synapse-env secret (postgres-password key)
- Bridge tokens: {bridge}-env secret (created separately)
- Registration files: mautrix-{bridge}-registration secret (from Task 5)

### Module Structure
```nix
kubernetes.resources = {
  deployments."mautrix-{bridge}" = { ... };
  services."mautrix-{bridge}" = { ... };
  persistentVolumeClaims."mautrix-whatsapp-data" = { ... }; # WhatsApp only
};
```

### Version Selection
- Used recent stable versions from mautrix releases
- Slack: v0.1.3 (latest from search results)
- Discord: v0.6.0 (common stable version)
- WhatsApp: v0.11.1 (recent stable, v26.01 is latest but v0.11.1 is stable)

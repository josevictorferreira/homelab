# Matrix Bridges - Decisions

## Architecture Decisions
- Using Synapse as Matrix homeserver (self-hosted)
- LAN-only access, federation disabled
- Using mautrix family for bridges (Slack, Discord, WhatsApp)
- Bridged rooms forced unencrypted (relay-bot mode)
- Reusing existing shared Postgres + Redis instances
- Internal DNS via Blocky pointing to shared Cilium ingress IP 10.10.10.110

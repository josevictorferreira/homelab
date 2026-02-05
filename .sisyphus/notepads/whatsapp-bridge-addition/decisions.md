# WhatsApp Bridge Addition - Decisions

## [2026-02-05] Initial design
- Bridge image: ghcr.io/mautrix/whatsapp:v0.11.1
- Namespace: applications (not matrix)
- Storage: 1Gi PVC (rook-ceph-block) for WhatsApp sessions
- Synapse URL: http://matrix.matrix.svc.cluster.local:8008
- Bridge mode: relaybot

# Architectural Decisions

## [2026-02-05] Initial Design
- **Image**: ghcr.io/openclaw/openclaw:latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5
- **Exposure**: LoadBalancer service (Cilium IPAM), no Ingress
- **Modeling**: Release submodule (NOT upstream OCI helm chart)
- **Secrets**: Gateway token only via SOPS
- **Storage**: 10Gi PVC on rook-ceph-block

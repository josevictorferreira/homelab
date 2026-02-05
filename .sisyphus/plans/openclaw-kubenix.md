# OpenClaw Kubernetes on Homelab (kubenix)

## PLAN METADATA
- **Created**: 2026-02-05
- **Status**: READY
- **Complexity**: MEDIUM
- **Est. Tasks**: 4
- **Dependencies**: kubenix, SOPS, Flux

## CONTEXT

User request: Install OpenClaw Kubernetes (from https://github.com/feiskyer/openclaw-kubernetes) into homelab cluster using kubenix patterns.

**Decisions Made**:
- Modeling: Release submodule re-impl (bjw-s app-template) NOT upstream OCI helm chart
- Image: `ghcr.io/openclaw/openclaw:latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5`
- Exposure: LoadBalancer service (Cilium LB IPAM) - disable ingress
- Secrets: Gateway token only (`OPENCLAW_GATEWAY_TOKEN`)
- Namespace: `homelab.kubernetes.namespaces.applications`

**Key Requirements**:
- Required env: `NODE_ENV=production`, `OPENCLAW_DATA_DIR=/home/node/.openclaw`, `OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json`
- Gateway token: `openssl rand -hex 32` (stored in SOPS)
- Port: 18789 (gateway), 18790 (bridge - optional)
- Persistence: 10Gi PVC (rook-ceph-block)
- Config format: JSON5 at /home/node/.openclaw/openclaw.json

**Upstream Spec**:
- Resources: 1 StatefulSet + LoadBalancer Service + SA + ConfigMap + Secret
- No CRDs, webhooks, or init containers needed
- Config: `openclaw.json` with `gateway.port` (18789) and `logging.level` (info)

## TASKS

### Phase 1: Setup Secrets

- [ ] **Task 1.1**: Add `openclaw_gateway_token` to `secrets/k8s-secrets.enc.yaml` (CAN_PARALLELIZE: True, conflicts=[])
  - Generate token: `openssl rand -hex 32`
  - Edit via `make secrets`, select k8s-secrets.enc.yaml
  - Add entry: `openclaw_gateway_token: <generated-token>`
  - Save and verify encryption

### Phase 2: Create Kubenix Modules

- [ ] **Task 2.1**: Create `modules/kubenix/apps/openclaw.nix` (CAN_PARALLELIZE: False, depends=[1.1], conflicts=[2.2])
  - Use release submodule pattern (see ntfy.nix reference)
  - Image: `ghcr.io/openclaw/openclaw:latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5`
  - Port: 18789
  - secretName: `openclaw-secrets`
  - command: `["node", "dist/index.js", "gateway", "--allow-unconfigured"]`
  - persistence: 10Gi PVC at /home/node/.openclaw
  - config: openclaw.json with gateway{port:18789,bind:"0.0.0.0"}, logging{level:"info"}
  - values: override ingress.main.enabled=false

- [ ] **Task 2.2**: Create `modules/kubenix/apps/openclaw-config.enc.nix` (CAN_PARALLELIZE: False, depends=[1.1], conflicts=[2.1])
  - Define Secret `openclaw-secrets` in applications namespace
  - stringData: NODE_ENV="production", OPENCLAW_DATA_DIR="/home/node/.openclaw", OPENCLAW_CONFIG_PATH="/home/node/.openclaw/openclaw.json", OPENCLAW_GATEWAY_TOKEN=(ref sops)

### Phase 3: Deploy and Verify

- [ ] **Task 3.1**: Run manifest pipeline and deploy (CAN_PARALLELIZE: False, depends=[2.1, 2.2])
  - Run: `make manifests` (gmanifests→vmanifests→umanifests→emanifests)
  - Verify: `.k8s/apps/openclaw.enc.yaml` and `openclaw-config.enc.yaml` exist
  - Check LSP diagnostics at project level (ZERO errors)
  - Commit generated manifests
  - Flux sync: `make reconcile`
  - Wait for StatefulSet ready: `kubectl -n applications wait --for=condition=ready pod -l app.kubernetes.io/name=openclaw --timeout=5m`
  - Check LoadBalancer IP: `kubectl -n applications get svc openclaw -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
  - Test gateway: `curl http://<LB-IP>:18789/health`

## VERIFICATION CRITERIA

- [ ] `make manifests` completes with exit code 0
- [ ] Project-level `lsp_diagnostics` returns ZERO errors
- [ ] `.k8s/apps/openclaw.enc.yaml` contains encrypted manifests
- [ ] StatefulSet `openclaw` reaches ready state
- [ ] LoadBalancer Service assigns IP from Cilium IPAM pool
- [ ] Health endpoint returns HTTP 200: `GET http://<LB-IP>:18789/health`
- [ ] Gateway token present in pod: `kubectl -n applications exec openclaw-0 -- env | grep OPENCLAW_GATEWAY_TOKEN`
- [ ] PVC bound and mounted at /home/node/.openclaw

## COMPLETION CRITERIA

ALL tasks checked off AND all verification criteria pass.

## NOTES

- Upstream chart uses init container to seed config; release submodule mounts ConfigMap directly
- Default storage requirement: 10Gi minimum (upstream spec)
- Gateway port 18789 exposed via LoadBalancer (no Ingress needed)
- Image pinned with digest to prevent unexpected updates

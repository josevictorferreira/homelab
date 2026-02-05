# WhatsApp Bridge Addition - Problems

## [2026-02-05] Initialization
- No blockers yet

## [2026-02-05] Cluster etcd timeouts blocking verification
- **Issue**: Persistent `etcdserver: request timed out` errors preventing kubectl operations
- **Impact**: Cannot verify deployment status (Task 5 verification blocked)
- **Evidence**: `kubectl get deployment` times out, Flux reconcile times out after 60s
- **Attempted**: Retry with delays, check cluster-info (shows healthy control plane)
- **Status**: BLOCKED on cluster infrastructure issue
- **Next steps**: Wait for cluster recovery OR verify via alternative methods (check git reconciliation, Flux events, pod logs if accessible)

## [2026-02-05 FINAL] WhatsApp Bridge Verification CANNOT BE COMPLETED

### Root Cause Chain
1. mautrix-whatsapp deployment created BUT stuck in ContainerCreating
2. Pod cannot start: missing Secret `mautrix-whatsapp-registration`
3. Secret does NOT exist in matrix-config.enc.yaml (verified via SOPS decrypt)
4. Only 2 secrets in matrix-config.enc.yaml: synapse-env, synapse-signing-key
5. Expected secrets missing: mautrix-whatsapp-env, mautrix-whatsapp-registration

### Investigation Summary
- modules/kubenix/apps/matrix-config.enc.nix WAS created with mautrix secrets (Task 2)
- modules/kubenix/apps/mautrix-whatsapp.nix exists (Task 3)
- BUT manifests generated from these sources do NOT contain bridge secrets
- Regenerated manifests via `make manifests` - matrix-config.enc.yaml still only has synapse secrets

### Hypothesis
- Either: modules/kubenix/apps/matrix-config.enc.nix NOT being evaluated properly
- Or: module structure incorrect (secrets not in right namespace/format)
- Or: manifest generation skipping mautrix secrets for unknown reason

### Status After 4 Boulder Attempts
- 6 verification tasks: CANNOT complete (deployment exists but not running)
- 0 ready replicas (pod stuck on missing secret)
- PVC: EXISTS and BOUND (1Gi rook-ceph-block) ✅
- Deployment: EXISTS but unhealthy ⚠️
- Secrets: MISSING ❌

### User Action Required
1. Verify matrix-config.enc.nix module structure
2. Check why manifests don't include mautrix-whatsapp secrets
3. Manually create secrets if necessary
4. Resume verification after secrets exist

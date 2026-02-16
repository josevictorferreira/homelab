# ProtonMail Bridge Deployment Plan

## TL;DR

**Email Bridge Only** - Proton Calendar has no self-hosted bridge solution available.

**Goal**: Deploy ProtonMail IMAP/SMTP bridge accessible within cluster for email automation/notifications.

**Deliverables**:
- `protonmail-bridge.nix` - StatefulSet exposing IMAP(143)/SMTP(25)
- `protonmail-bridge-config.enc.nix` - Configuration/secret definitions
- Secrets entry for bridge initialization credentials
- Interactive login procedure via `kubectl exec`

**Estimated Effort**: Medium
**Parallel Execution**: NO (sequential steps)
**Critical Path**: Setup code → Generate manifests → Interactive auth → Verification

---

## Context

### Repository Analyzed
**Source**: https://github.com/shenxn/protonmail-bridge-docker
- **Image**: `shenxn/protonmail-bridge`
- **Tags**: `latest` (deb-based, amd64 only) / `build` (source, multi-arch including arm64)
- **Ports**: 25/tcp (SMTP), 143/tcp (IMAP)
- **Volume**: `/root` for persistent auth state
- **Architecture**: Your cluster has arm64 nodes (lab-pi-bk) → Use `build` tag

### Critical Finding: Proton Calendar = NOT POSSIBLE
**ProtonMail Bridge is EMAIL ONLY.** There is no self-hosted solution for Proton Calendar.

**Why**: Proton's calendar infrastructure does not expose CalDAV or any sync protocol. The official Proton Bridge application (GitHub: ProtonMail/proton-bridge) is explicitly email-only.

**GitHub Issue Reference**: https://github.com/ProtonMail/proton-bridge/issues/223 (closed - no calendar support planned via bridge)

**Calendar Options**:
1. Use Proton's official apps (mobile/web/desktop) - No self-hosted option
2. Migrate to provider with CalDAV (Nextcloud, Radicale, etc.) - Recommended if you need self-hosted calendar
3. Manual export/import - Not automated sync

### Authentication Challenge
ProtonMail Bridge requires **interactive CLI login**:
1. Run `init` command
2. Enter ProtonMail username/password
3. If 2FA enabled, enter 2FA code
4. Credentials stored in `/root` volume

This is a **one-time initialization** - once authenticated, the bridge runs as daemon.

### User Requirements Confirmed
- **Scope**: Email bridge + Calendar (Calendar limitation explained above)
- **Auth Method**: Interactive pod access via `kubectl exec -it`
- **Access Pattern**: Internal cluster only (IMAP/SMTP for other pods)
- **Storage**: Persistent `/root` volume required

---

## Work Objectives

### Core Objective
Deploy ProtonMail Bridge as a StatefulSet in the applications namespace, exposing IMAP(143) and SMTP(25) ports cluster-internally, with persistent storage for authentication state.

### Concrete Deliverables
1. `modules/kubenix/apps/protonmail-bridge.nix` - Main deployment
2. `modules/kubenix/apps/protonmail-bridge-config.enc.nix` - Companion config (minimal, bridge has no config file)
3. Secrets entry in `secrets/k8s-secrets.enc.yaml` (if needed for any config)
4. Interactive login completed via pod exec

### Definition of Done
- [ ] Bridge pod running with "authenticated" status in logs
- [ ] IMAP port (143) accessible from other pods via cluster DNS
- [ ] SMTP port (25) accessible from other pods via cluster DNS
- [ ] Test email can be sent via SMTP from test pod

### Must Have
- [ ] StatefulSet with persistent PVC at `/root`
- [ ] Multi-arch image support (arm64 for pi-bk node)
- [ ] Service exposing ports 25 and 143
- [ ] Interactive login procedure documented

### Must NOT Have (Guardrails)
- [ ] NO external access (internal cluster only - security)
- [ ] NO ingress (not a web service)
- [ ] NO hardcoded credentials (SOPS for any config)

---

## Verification Strategy

### Agent-Executed QA Scenarios

**Scenario 1: Bridge Pod Running**
Tool: Bash (kubectl)
Preconditions: Manifests applied, pod scheduled
Steps:
  1. `kubectl get pod -n applications -l app=protonmail-bridge`
  2. Assert: Pod status is "Running"
  3. `kubectl logs -n applications -l app=protonmail-bridge --tail=20`
  4. Assert: Logs show "IMAP server started" and "SMTP server started"
Expected Result: Bridge running and listening on both ports
Evidence: Terminal output capture

**Scenario 2: Service Endpoints Available**
Tool: Bash (kubectl)
Preconditions: Bridge pod running
Steps:
  1. `kubectl get svc -n applications protonmail-bridge`
  2. Assert: Service shows ports 25 and 143
  3. `kubectl describe svc -n applications protonmail-bridge | grep Endpoints`
  4. Assert: Endpoints show pod IPs (not <none>)
Expected Result: Service correctly routes to bridge pods
Evidence: kubectl output

**Scenario 3: Authentication Completed**
Tool: Bash (kubectl exec interactive)
Preconditions: Bridge pod running, not yet authenticated
Steps:
  1. `kubectl exec -it -n applications protonmail-bridge-0 -- /bin/bash`
  2. Inside pod: `protonmail-bridge --cli`
  3. Send: "login" command with credentials
  4. If 2FA: Send 2FA code
  5. Send: "info" command
  6. Assert: Output shows connected accounts and IMAP/SMTP settings
  7. Exit CLI (Ctrl+C), exit pod
Expected Result: Bridge shows authenticated status with account info
Evidence: Terminal output capture

**Scenario 4: IMAP Connectivity Test**
Tool: Bash (kubectl run temp pod)
Preconditions: Bridge authenticated and running
Steps:
  1. `kubectl run -it --rm --restart=Never test-imap -n applications --image=busybox:1.37 -- /bin/sh`
  2. Inside: `nc -zv protonmail-bridge 143`
  3. Assert: Connection succeeds (open)
Expected Result: IMAP port accessible from other pods
Evidence: nc output

**Scenario 5: SMTP Connectivity Test**
Tool: Bash (kubectl run temp pod)
Preconditions: Bridge authenticated and running
Steps:
  1. `kubectl run -it --rm --restart=Never test-smtp -n applications --image=busybox:1.37 -- /bin/sh`
  2. Inside: `nc -zv protonmail-bridge 25`
  3. Assert: Connection succeeds (open)
Expected Result: SMTP port accessible from other pods
Evidence: nc output

---

## Execution Strategy

### Sequential Steps (No Parallelization)

**Phase 1: Infrastructure Setup**
1. Create app definition file
2. Create companion config file
3. Add secrets (if needed)
4. Generate manifests

**Phase 2: Deployment**
5. Apply manifests
6. Verify pod running
7. Interactive authentication

**Phase 3: Verification**
8. Test connectivity
9. Document connection details

---

## TODOs

- [ ] 1. Create protonmail-bridge.nix

  **What to do**:
  - Create `modules/kubenix/apps/protonmail-bridge.nix` with StatefulSet
  - Use `shenxn/protonmail-bridge:build` image (multi-arch)
  - Expose ports 25 (SMTP) and 143 (IMAP)
  - Create PVC at `/root` with rook-ceph-block storage class
  - Add Service with cluster-internal access only
  - Add readiness probe (check if bridge is listening)
  
  **Must NOT do**:
  - NO LoadBalancer or NodePort (internal only)
  - NO ingress
  - NO hardcoded credentials
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `writing-nix-code`
  - **Reason**: Requires Nix expression writing, not complex logic
  
  **Parallelization**:
  - **Can Run In Parallel**: NO (first step)
  - **Blocks**: Task 2, 3, 4, 5
  
  **References**:
  - Pattern: `modules/kubenix/apps/mautrix-whatsapp.nix` - Raw K8s resources pattern
  - PVC: `modules/kubenix/apps/mautrix-whatsapp.nix` lines 10-17
  - Service: `modules/kubenix/apps/mautrix-whatsapp.nix` lines 19-31
  - StatefulSet: Reference `modules/kubenix/apps/postgresql-18.nix` for StatefulSet spec
  - Image digests: Check https://hub.docker.com/r/shenxn/protonmail-bridge/tags
  
  **Acceptance Criteria**:
  - [ ] File created at `modules/kubenix/apps/protonmail-bridge.nix`
  - [ ] Uses multi-arch `build` tag image
  - [ ] StatefulSet with replicas=1
  - [ ] PVC mounted at `/root`
  - [ ] Service exposes ports 25 and 143
  - [ ] Resource limits defined (reasonable for mail bridge: 256Mi-512Mi RAM)
  
  **Agent-Executed QA Scenario**:
  ```
  Scenario: Nix file valid
    Tool: Bash
    Steps:
      1. `nix build .#gen-manifests --dry-run 2>&1 | grep -i proton`
      2. Assert: No errors, file is valid Nix
    Expected: File passes syntax check
  ```
  
  **Commit**: YES
  - Message: `feat(apps): add protonmail-bridge deployment`
  - Files: `modules/kubenix/apps/protonmail-bridge.nix`
  - Pre-commit: `make check` passes

---

- [ ] 2. Create protonmail-bridge-config.enc.nix

  **What to do**:
  - Create companion file `protonmail-bridge-config.enc.nix`
  - Most bridge config is interactive, but create structure for any env vars
  - Minimal placeholder (bridge uses interactive CLI, not config files)
  
  **Must NOT do**:
  - NO hardcoded credentials (use `kubenix.lib.secretsFor`)
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  
  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 1 for context)
  - **Blocked By**: Task 1
  
  **References**:
  - Pattern: `modules/kubenix/apps/ntfy-secrets.enc.nix`
  - Secret helper: `kubenix.lib.secretsFor`
  
  **Acceptance Criteria**:
  - [ ] File created at `modules/kubenix/apps/protonmail-bridge-config.enc.nix`
  - [ ] Uses `kubenix.lib.secretsFor` pattern if any secrets needed
  - [ ] Included in main protonmail-bridge.nix
  
  **Agent-Executed QA Scenario**:
  ```
  Scenario: Config file referenced
    Tool: Bash
    Steps:
      1. `grep "protonmail-bridge-config" modules/kubenix/apps/protonmail-bridge.nix`
      2. Assert: Reference found
    Expected: Config file is wired into main module
  ```
  
  **Commit**: GROUP with Task 1

---

- [ ] 3. Generate Manifests

  **What to do**:
  - Run `make manifests` to generate K8s YAML
  - Verify protonmail-bridge manifests created in `.k8s/apps/`
  
  **Must NOT do**:
  - NO manual editing of `.k8s/*.yaml` files
  
  **Recommended Agent Profile**:
  - **Category**: `quick`
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocked By**: Task 1, 2
  
  **Acceptance Criteria**:
  - [ ] `make manifests` completes without errors
  - [ ] Files exist: `.k8s/apps/protonmail-bridge.yaml`, `.k8s/apps/protonmail-bridge-config.enc.yaml`
  
  **Agent-Executed QA Scenario**:
  ```
  Scenario: Manifests generated
    Tool: Bash
    Steps:
      1. `ls -la .k8s/apps/ | grep proton`
      2. Assert: Files exist and are encrypted (.enc.yaml)
    Expected: Manifests present
  ```
  
  **Commit**: YES
  - Message: `chore(manifests): generate protonmail-bridge`
  - Files: `.k8s/apps/protonmail-bridge.yaml`, `.k8s/apps/protonmail-bridge-config.enc.yaml`

---

- [ ] 4. Apply Manifests to Cluster

  **What to do**:
  - Wait for Flux to auto-apply OR manually apply if needed
  - Verify pod scheduled and running
  - Check logs for "IMAP server started" message
  
  **Must NOT do**:
  - NO direct `kubectl apply` (prefer Flux GitOps)
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `kubernetes-tools`
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocked By**: Task 3
  
  **Acceptance Criteria**:
  - [ ] `kubectl get pod -n applications protonmail-bridge-0` shows "Running"
  - [ ] Logs show IMAP and SMTP servers started
  - [ ] PVC bound and mounted
  
  **Agent-Executed QA Scenario**:
  ```
  Scenario: Bridge running
    Tool: Bash (kubectl)
    Steps:
      1. `kubectl wait -n applications pod/protonmail-bridge-0 --for=condition=Ready --timeout=120s`
      2. `kubectl logs -n applications protonmail-bridge-0 | grep -i "imap.*started"`
      3. Assert: Log lines found
    Expected: Bridge pod ready and listening
  ```
  
  **Commit**: NO (runtime verification)

---

- [ ] 5. Interactive Authentication

  **What to do**:
  - Exec into pod: `kubectl exec -it -n applications protonmail-bridge-0 -- /bin/bash`
  - Start bridge CLI: `protonmail-bridge --cli`
  - Follow prompts to login:
    - Enter ProtonMail username
    - Enter password
    - If 2FA enabled, enter code
  - Verify with `info` command
  - Exit CLI (Ctrl+C), exit pod
  
  **Must NOT do**:
  - NO hardcoded credentials in any files
  - NO storing credentials in ConfigMaps
  
  **Critical Warning**: Authentication state is stored in `/root` (PVC). If PVC is lost, re-auth required.
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocked By**: Task 4
  
  **References**:
  - Bridge docs: https://github.com/shenxn/protonmail-bridge-docker#initialization
  
  **Acceptance Criteria**:
  - [ ] Bridge shows as "connected" in `info` output
  - [ ] IMAP/SMTP credentials displayed for client configuration
  - [ ] Credentials persisted to PVC (`/root/.config/protonmail/bridge/`)
  
  **Agent-Executed QA Scenario**:
  ```
  Scenario: Authentication successful
    Tool: Bash (kubectl exec)
    Steps:
      1. `kubectl exec -n applications protonmail-bridge-0 -- cat /root/.config/protonmail/bridge/info.json 2>/dev/null || echo "Not found"`
      2. Assert: File exists (auth state persisted)
      3. `kubectl logs -n applications protonmail-bridge-0 | grep -i "account.*connected\|login.*successful"`
      4. Assert: Connection message in logs
    Expected: Bridge authenticated and state persisted
  ```
  
  **Commit**: NO (runtime operation)

---

- [ ] 6. Verify Connectivity

  **What to do**:
  - Test IMAP port from another pod
  - Test SMTP port from another pod
  - Document connection details
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocked By**: Task 5
  
  **Acceptance Criteria**:
  - [ ] IMAP port 143 accessible from test pod
  - [ ] SMTP port 25 accessible from test pod
  - [ ] Connection details documented (hostname, ports, credentials)
  
  **Agent-Executed QA Scenarios**:
  ```
  Scenario: IMAP connectivity
    Tool: Bash (kubectl run)
    Steps:
      1. `kubectl run -n applications test-imap --rm -it --restart=Never --image=busybox:1.37 -- nc -zv protonmail-bridge 143`
      2. Assert: Exit code 0, "open" in output
    Expected: IMAP port reachable
  
  Scenario: SMTP connectivity
    Tool: Bash (kubectl run)
    Steps:
      1. `kubectl run -n applications test-smtp --rm -it --restart=Never --image=busybox:1.37 -- nc -zv protonmail-bridge 25`
      2. Assert: Exit code 0, "open" in output
    Expected: SMTP port reachable
  ```
  
  **Commit**: NO (verification step)

---

## Connection Details (Post-Setup)

After successful authentication, the bridge will display connection info similar to:

```
IMAP Server:  protonmail-bridge.applications.svc.cluster.local:143
SMTP Server:  protonmail-bridge.applications.svc.cluster.local:25
Username:     <your-proton-email@example.com>
Password:     <bridge-generated-app-password>
```

**For other pods in cluster**:
- IMAP: `protonmail-bridge.applications.svc.cluster.local:143`
- SMTP: `protonmail-bridge.applications.svc.cluster.local:25`

**Note**: The bridge generates unique app passwords - do NOT use your Proton account password in email clients.

---

## Proton Calendar Alternative

Since Proton Calendar cannot be bridged, here are self-hosted calendar alternatives:

### Option 1: Radicale (Lightweight CalDAV)
- Simple CalDAV/CardDAV server
- Good for personal use
- Can be deployed via kubenix similar to other apps

### Option 2: Nextcloud Calendar
- Full featured (calendar + files + etc)
- Heavier but feature-rich
- Already have Nextcloud? Use its calendar

### Option 3: Keep Proton Calendar
- Use Proton's web/mobile apps
- No self-hosting, but maintains E2E encryption
- Accept limitation for calendar

**Recommendation**: If you need self-hosted calendar, Radicale is simplest. Deploy as separate kubenix app.

---

## Commit Strategy

| After Task | Message | Files |
|------------|---------|-------|
| 1+2 | `feat(apps): add protonmail-bridge deployment` | `modules/kubenix/apps/protonmail-bridge.nix`, `modules/kubenix/apps/protonmail-bridge-config.enc.nix` |
| 3 | `chore(manifests): generate protonmail-bridge` | `.k8s/apps/protonmail-bridge.yaml`, `.k8s/apps/protonmail-bridge-config.enc.yaml` |

---

## Success Criteria

### Final Verification Commands
```bash
# Check pod running
kubectl get pod -n applications protonmail-bridge-0

# Check logs for IMAP/SMTP started
kubectl logs -n applications protonmail-bridge-0 | grep -i "started"

# Test connectivity
kubectl run -n applications test --rm -it --restart=Never --image=busybox:1.37 -- nc -zv protonmail-bridge 143
kubectl run -n applications test --rm -it --restart=Never --image=busybox:1.37 -- nc -zv protonmail-bridge 25
```

### Final Checklist
- [ ] Bridge pod running and authenticated
- [ ] IMAP (143) and SMTP (25) ports accessible internally
- [ ] Persistent volume stores auth state
- [ ] Documentation complete for connection details
- [ ] Calendar limitation acknowledged (user informed)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| PVC loss = re-auth needed | Medium | Document re-auth procedure; auth is quick |
| Proton API changes | Low | Bridge image maintained by community; update image tag |
| No calendar bridge | High (functional) | User informed; alternatives provided |
| Interactive auth complexity | Medium | Clear step-by-step instructions in plan |

---

## Notes for Executor

1. **Authentication is manual**: Plan includes detailed interactive auth steps
2. **Use `build` tag**: For arm64 compatibility with pi-bk node
3. **StatefulSet not Deployment**: Ensures PVC is properly bound and survives restarts
4. **No ingress**: This is a mail bridge, not a web service
5. **Internal only**: Service should be ClusterIP, not LoadBalancer
6. **Calendar limitation**: User wants calendar but it's not possible - ensure they're aware

# Plan: `openclaw-nix` kubenix app (new image) + keep existing `openclaw`

## TL;DR
> Add new kubenix app `openclaw-nix` using image `ghcr.io/josevictorferreira/openclaw-nix:latest`, no initContainers, reuse `openclaw-secrets`, mount workspace on CephFS subPath `openclaw`, keep existing `modules/kubenix/apps/openclaw.nix` unchanged + working.

**Deliverables**
- `modules/kubenix/apps/openclaw-nix.nix`
- Generated manifests in `.k8s/apps/openclaw-nix*.yaml` (Deployment, ConfigMap, Service (ClusterIP), PVCs, RBAC)

**Effort**: Medium
**Parallelism**: YES (3 waves)

---

## Context

### Original Request (verbatim-ish)
- New kubenix service `openclaw-nix` (may use current release submodule).
- Keep current `openclaw.nix` + `openclaw-config.enc.nix` as-is and working.
- Workspace volume must use shared CephFS root folder `openclaw` so it’s editable remotely.
- Other volumes: block storage.
- OpenClaw config must be the same as current `openclaw` config.
- No initContainers (startup delay target).
- Ensure same cluster access from inside pod as current openclaw.

### Confirmed Decisions
- Image: `ghcr.io/josevictorferreira/openclaw-nix:latest`
- Exposure: **ClusterIP** service only; no LB, no Ingress.
- Keep Tailscale sidecar; `TS_HOSTNAME=openclaw-nix`.
- Reuse Secret name `openclaw-secrets` (do not change that module).
- Override in Deployment env: `OPENCLAW_CONFIG_PATH=/config/openclaw.json`, `OPENCLAW_DATA_DIR=/state/openclaw`, `HOME=/state/home`.
- Config source: new ConfigMap named `openclaw-nix` containing **exact same JSON content** as current openclaw’s ConfigMap `openclaw.json`.
- Workspace: existingClaim `cephfs-shared-storage-root` + `subPath: openclaw` mounted at `/home/node/.openclaw/workspace`.
- Persistence:
  - `/config`: emptyDir
  - `/state`: PVC (rook-ceph-block, RWO, 10Gi)
  - `/logs`: PVC (rook-ceph-block, RWO, 1Gi)
  - tailscale state: PVC (rook-ceph-block, RWO, 1Gi)
- Runtime config patching: do a fast JSON patch in the main container command to ensure matrix+whatsapp enabled + present in `plugins.allow`.
- Copy pod DNS settings from current openclaw (`dnsPolicy=None`, nameservers `10.43.0.10`, `100.100.100.100`).

### Key Existing References
- Current app blueprint: `modules/kubenix/apps/openclaw.nix`
  - RBAC cluster-admin pattern (SA + ClusterRole + CRB): ~L8-41
  - release instance wiring: ~L43+
  - dnsPolicy/dnsConfig + ingress disabled: ~L279-303
  - tailscale sidecar + volumes: ~L351-395
- Secrets: `modules/kubenix/apps/openclaw-config.enc.nix` (Secret `openclaw-secrets`)
- Shared CephFS PVC: `modules/kubenix/apps/shared-storage-pvc.nix` (PVC `cephfs-shared-storage-root`)
- Release wrapper: `modules/kubenix/_submodules/release.nix` (bjw-s app-template v4.2.0)
- Current rendered manifests (for parity check): `.k8s/apps/openclaw.yaml`

---

## Work Objectives

### Core Objective
Deploy `openclaw-nix` with new image + persistence layout, while preserving existing `openclaw` app unchanged.

### Must Have
- No initContainers.
- Workspace on CephFS root `/openclaw` (subPath) mounted at `/home/node/.openclaw/workspace`.
- `/state` and `/logs` on rook-ceph-block PVCs.
- Tailscale sidecar works (tun + state PVC) with non-colliding hostname.
- Cluster-admin access inside pod via SA + token.

### Must NOT Have
- Do not modify `modules/kubenix/apps/openclaw.nix`.
- Do not modify `modules/kubenix/apps/openclaw-config.enc.nix`.
- Do not add initContainers.
- Do not change secret keys/values.

---

## Verification Strategy

> Agent-executed only; no manual checks.

### Primary commands
- `git diff --stat`
- `make manifests` (requires new files staged: flake evaluates git tree)
- Validate generated `.k8s/apps/openclaw-nix*.yaml` matches plan.

### Runtime QA (cluster)
- `kubectl get -n apps deploy/openclaw-nix pod,svc,pvc`
- `kubectl logs -n apps deploy/openclaw-nix -c main --tail=200`
- `kubectl exec -n apps deploy/openclaw-nix -c main -- sh -lc 'test -w /config && test -w /state && test -w /logs'`
- Verify config patch:
  - `kubectl exec ... -- sh -lc 'jq -r .plugins.allow /config/openclaw.json'`
- Verify k8s API access (no kubectl needed in image):
  - `kubectl exec ... -- sh -lc 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt; curl -fsS --cacert $CACERT -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api | jq -r .versions[0]'`

---

## Execution Strategy (parallel waves)

Wave 1 (scaffold + config/persistence) — parallel

Wave 2 (command wrapper + DNS + tailscale + RBAC) — parallel

Wave 3 (manifests + cluster QA) — parallel

---

## TODOs


- [ ] 1. Add new kubenix app module `openclaw-nix` (scaffold)

  **What to do**:
  - Create `modules/kubenix/apps/openclaw-nix.nix`.
  - Define `submodules.instances.openclaw-nix` using `submodule = "release"`.
  - Set args: namespace apps, image `ghcr.io/josevictorferreira/openclaw-nix:latest`, port 18789, replicas 1, `secretName = "openclaw-secrets"`.
  - Keep `ingress.main.enabled = false`.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 1
  - Blocks: 2-8

  **References**:
  - Blueprint: `modules/kubenix/apps/openclaw.nix:43-111` (release instance args)
  - Wrapper defaults: `modules/kubenix/_submodules/release.nix` (service defaults to LB)

  **Acceptance Criteria**:
  - [ ] Only new file added; no edits to existing openclaw modules.

  **QA Scenarios**:
  ```
  Scenario: File exists and is staged
    Tool: Bash
    Steps:
      1. test -f modules/kubenix/apps/openclaw-nix.nix
      2. git add modules/kubenix/apps/openclaw-nix.nix
      3. git diff --cached --stat | tee .sisyphus/evidence/task-1-staged-stat.txt
    Expected Result: shows only that file
    Evidence: .sisyphus/evidence/task-1-staged-stat.txt
  ```

- [ ] 2. Create `openclaw-nix` ConfigMap with exact same `openclaw.json` content

  **What to do**:
  - In `openclaw-nix.nix`, use release `config` feature to create ConfigMap named `openclaw-nix`.
  - `config.filename = "config-template.json"`.
  - `config.data` must be copy/paste of the JSON attrset from `modules/kubenix/apps/openclaw.nix` (no edits, incl the known OPENROUTER_API_KEY mapping bug).
  - Mount path should NOT be `/config` (because `/config` must be writable); mount at `/etc/openclaw` so file becomes `/etc/openclaw/config-template.json`.

  **Must NOT do**:
  - Do not "fix" config; keep byte-equivalent semantic content.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 1
  - Blocked By: 1
  - Blocks: 6

  **References**:
  - Source of truth: `modules/kubenix/apps/openclaw.nix:140-276` (config attrset)
  - Current rendered proof: `.k8s/apps/openclaw.yaml` (ConfigMap `openclaw` contains `openclaw.json`)

  **Acceptance Criteria**:
  - [ ] Generated YAML includes `kind: ConfigMap` name `openclaw-nix` and key `config-template.json`.

  **QA Scenarios**:
  ```
  Scenario: ConfigMap rendered and key present
    Tool: Bash
    Steps:
      1. make manifests |& tee .sisyphus/evidence/task-2-make-manifests.txt
      2. rg -n "kind: ConfigMap" .k8s/apps/openclaw-nix.yaml
      3. rg -n "name: openclaw-nix" .k8s/apps/openclaw-nix.yaml
      4. rg -n "config-template\\.json:" .k8s/apps/openclaw-nix.yaml
    Expected Result: all greps hit
    Evidence: .sisyphus/evidence/task-2-make-manifests.txt
  ```

- [ ] 3. Service exposure: ClusterIP only, no Ingress

  **What to do**:
  - Override helm values so Service is ClusterIP.
  - Ensure ingress stays disabled.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 1
  - Blocked By: 1
  - Blocks: 9

  **References**:
  - Default to override: `modules/kubenix/_submodules/release.nix` (service.main.type = LoadBalancer)
  - Openclaw disables ingress: `modules/kubenix/apps/openclaw.nix:279`

  **Acceptance Criteria**:
  - [ ] `.k8s/apps/openclaw-nix.yaml` Service `type: ClusterIP`.
  - [ ] No Ingress in `.k8s/apps/openclaw-nix.yaml`.

  **QA Scenarios**:
  ```
  Scenario: Service type check
    Tool: Bash
    Steps:
      1. make manifests
      2. rg -n "^kind: Service" .k8s/apps/openclaw-nix.yaml
      3. rg -n "type: ClusterIP" .k8s/apps/openclaw-nix.yaml
      4. ! rg -n "^kind: Ingress" .k8s/apps/openclaw-nix.yaml
    Expected Result: ClusterIP present; ingress absent
    Evidence: .sisyphus/evidence/task-3-service.txt
  ```

- [ ] 4. RBAC: cluster-admin access inside pod (separate names)

  **What to do**:
  - Add ServiceAccount `openclaw-nix` (namespace apps).
  - Add ClusterRole `openclaw-nix-cluster-admin` with wildcard permissions.
  - Add ClusterRoleBinding to bind SA.
  - Wire chart values: `controllers.main.serviceAccount.name = "openclaw-nix"` + `defaultPodOptions.automountServiceAccountToken = true`.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 1
  - Blocked By: 1
  - Blocks: 9

  **References**:
  - Pattern: `modules/kubenix/apps/openclaw.nix:8-41` (SA/CR/CRB)
  - Token automount: `modules/kubenix/apps/openclaw.nix:284-285`

  **Acceptance Criteria**:
  - [ ] Generated YAML includes SA + ClusterRole + ClusterRoleBinding.

  **QA Scenarios**:
  ```
  Scenario: RBAC objects rendered
    Tool: Bash
    Steps:
      1. make manifests
      2. rg -n "kind: ServiceAccount" .k8s/apps/openclaw-nix.yaml
      3. rg -n "name: openclaw-nix" .k8s/apps/openclaw-nix.yaml
      4. rg -n "kind: ClusterRole" .k8s/apps/openclaw-nix.yaml
      5. rg -n "openclaw-nix-cluster-admin" .k8s/apps/openclaw-nix.yaml
    Expected Result: all present
    Evidence: .sisyphus/evidence/task-4-rbac.txt
  ```

- [ ] 5. Volumes + persistence (no initContainers)

  **What to do**:
  - Implement storage in `openclaw-nix.nix` (bjw-s app-template 4.x schema):
    - `/config`: `emptyDir` (writable) mounted to main container.
    - `/state`: PVC (rook-ceph-block, RWO, 10Gi) mounted to `/state` (name: `openclaw-nix-state`).
    - `/logs`: PVC (rook-ceph-block, RWO, 1Gi) mounted to `/logs` (name: `openclaw-nix-logs`).
    - Workspace: existingClaim `cephfs-shared-storage-root` mounted at `/home/node/.openclaw/workspace` with `subPath = "openclaw"`.
    - Tailscale state: PVC (rook-ceph-block, RWO, 1Gi) mounted at `/var/lib/tailscale` in `tailscale` container (name: `openclaw-nix-tailscale-state`).
    - Tailscale tun: hostPath `/dev/net/tun` mounted in `tailscale` container.
  - Ensure *no* `controllers.main.initContainers.*` defined.

  **Recommended Agent Profile**:
  - Category: `unspecified-high`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 1
  - Blocked By: 1
  - Blocks: 6-9

  **References**:
  - Openclaw tailscale+tun pattern: `modules/kubenix/apps/openclaw.nix:351-395`
  - Openclaw persistence pattern: `modules/kubenix/apps/openclaw.nix:104-111` + `:379-390`
  - Shared CephFS PVC: `modules/kubenix/apps/shared-storage-pvc.nix` (PVC `cephfs-shared-storage-root`)
  - app-template docs (persistence):
    - https://bjw-s-labs.github.io/helm-charts/docs/common-library/storage/
    - emptyDir: https://bjw-s-labs.github.io/helm-charts/docs/common-library/storage/types/emptyDir/
    - pvc: https://bjw-s-labs.github.io/helm-charts/docs/common-library/storage/types/persistentVolumeClaim/
    - subPath howto: https://bjw-s-labs.github.io/helm-charts/docs/app-template/howto/multiple-subpath/

  **Acceptance Criteria**:
  - [ ] Rendered YAML has volumeMounts for `/config`, `/state`, `/logs`, workspace mount, tailscale mounts.
  - [ ] Rendered YAML has 0 initContainers.

  **QA Scenarios**:
  ```
  Scenario: No initContainers and mounts present in rendered YAML
    Tool: Bash
    Steps:
      1. make manifests
      2. ! rg -n "initContainers:" .k8s/apps/openclaw-nix.yaml
      3. rg -n "mountPath: /config" .k8s/apps/openclaw-nix.yaml
      4. rg -n "mountPath: /state" .k8s/apps/openclaw-nix.yaml
      5. rg -n "mountPath: /logs" .k8s/apps/openclaw-nix.yaml
      6. rg -n "claimName: cephfs-shared-storage-root" .k8s/apps/openclaw-nix.yaml
      7. rg -n "path: /dev/net/tun" .k8s/apps/openclaw-nix.yaml
    Expected Result: no initContainers; expected mounts/volumes present
    Evidence: .sisyphus/evidence/task-5-volumes-no-init.txt
  ```

- [ ] 6. Config-template mount + writable `/config` (ConfigMap NOT mounted to /config)

  **What to do**:
  - Ensure ConfigMap key is mounted as `/etc/openclaw/config-template.json` (read-only).
  - Keep `/config` as emptyDir.
  - Ensure main command uses `/etc/openclaw/config-template.json` as the "source of truth" template.

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 2
  - Blocked By: 2, 5
  - Blocks: 7

  **References**:
  - Metis: ConfigMaps are read-only; copy into emptyDir before patching.
  - Image entrypoint contract: writes `/config/openclaw.json`.

  **Acceptance Criteria**:
  - [ ] Rendered YAML mounts ConfigMap at `/etc/openclaw/config-template.json` and mounts emptyDir at `/config`.

  **QA Scenarios**:
  ```
  Scenario: Template mount exists and /config is not a ConfigMap mount
    Tool: Bash
    Steps:
      1. make manifests
      2. rg -n "mountPath: /etc/openclaw" .k8s/apps/openclaw-nix.yaml
      3. rg -n "subPath: config-template\\.json" .k8s/apps/openclaw-nix.yaml
      4. rg -n "mountPath: /config" .k8s/apps/openclaw-nix.yaml
    Expected Result: template file mount + /config mount present
    Evidence: .sisyphus/evidence/task-6-template-mount.txt
  ```

- [ ] 7. Main container command wrapper: copy template → render `/config/openclaw.json` → JSON patch → exec gateway

  **What to do**:
  - Override `args.command` for `openclaw-nix` main container.
  - Wrapper responsibilities (NO initContainer, fast):
    1) Copy `/etc/openclaw/config-template.json` → `/config/openclaw.json`.
    2) Substitute allowlisted `${ENV}` placeholders (same allowlist as current openclaw):
       `OPENCLAW_MATRIX_TOKEN`, `ELEVENLABS_API_KEY`, `MOONSHOT_API_KEY`, `OPENROUTER_API_KEY`, `WHATSAPP_NUMBER`, `WHATSAPP_BOT_NUMBER`.
    3) Patch JSON to match current runtime behavior:
       - `.plugins.entries.matrix.enabled = true`
       - `.plugins.entries.whatsapp.enabled = true`
       - ensure `.plugins.allow` contains `matrix` + `whatsapp` (dedupe)
    4) `exec openclaw gateway --port 18789`.
  - Use `jq` for patching (present in image).

  **Must NOT do**:
  - No `npm install`, no network installers, no chown/chmod on volumes.

  **Recommended Agent Profile**:
  - Category: `unspecified-high`
  - Skills: `developing-containers`

  **Parallelization**:
  - Wave: 2
  - Blocked By: 5, 6
  - Blocks: 9

  **References**:
  - Current patch behavior reference: `modules/kubenix/apps/openclaw.nix` runtime script in `args.command` (top section).
  - Config baseline indicates why patch needed: `modules/kubenix/apps/openclaw.nix:202-255` (plugins.allow=["matrix"], whatsapp lacks enabled).
  - Do NOT replicate init-tools approach: `modules/kubenix/apps/openclaw.nix:396-498`.

  **Acceptance Criteria**:
  - [ ] Rendered YAML command contains `jq` patch steps.
  - [ ] Cluster QA shows `/config/openclaw.json` exists and `plugins.allow` includes whatsapp.

  **QA Scenarios**:
  ```
  Scenario: Rendered YAML includes wrapper command
    Tool: Bash
    Steps:
      1. make manifests
      2. rg -n "openclaw gateway" .k8s/apps/openclaw-nix.yaml
      3. rg -n "jq" .k8s/apps/openclaw-nix.yaml
    Expected Result: wrapper present
    Evidence: .sisyphus/evidence/task-7-command-render.txt

  Scenario: Runtime config patched
    Tool: Bash
    Steps:
      1. kubectl -n apps rollout status deploy/openclaw-nix --timeout=180s | tee .sisyphus/evidence/task-7-rollout.txt
      2. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc 'test -f /config/openclaw.json'
      3. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc 'jq -cr .plugins.allow /config/openclaw.json' | tee .sisyphus/evidence/task-7-plugins-allow.json
    Expected Result: allow list includes "matrix" and "whatsapp"
    Evidence: .sisyphus/evidence/task-7-plugins-allow.json
  ```

- [ ] 8. Env + securityContext overrides (reuse Secret but use new paths)

  **What to do**:
  - Keep `envFrom: secretRef openclaw-secrets`.
  - Override/define env vars in values for main container:
    - `OPENCLAW_CONFIG_PATH=/config/openclaw.json`
    - `OPENCLAW_DATA_DIR=/state/openclaw`
    - `HOME=/state/home`
  - Copy current dns + basic env conventions:
    - `dnsPolicy=None` + dnsConfig (nameservers/searches/options)
  - Default applied (mirror current openclaw): run as root for fewer CephFS perms surprises:
    - `controllers.main.containers.main.securityContext.runAsUser=0`, `runAsGroup=0`

  **Recommended Agent Profile**:
  - Category: `quick`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 2
  - Blocked By: 1
  - Blocks: 9

  **References**:
  - DNS+env pattern: `modules/kubenix/apps/openclaw.nix:279-309` (dnsPolicy, nameservers, ndots)
  - Security context: `modules/kubenix/apps/openclaw.nix:280-283`
  - Secret reuse: `modules/kubenix/apps/openclaw.nix` uses `secretName = "openclaw-secrets"`.

  **Acceptance Criteria**:
  - [ ] Rendered YAML shows overridden env vars and dnsConfig.

  **QA Scenarios**:
  ```
  Scenario: Env override shows inside pod
    Tool: Bash
    Steps:
      1. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc 'echo $OPENCLAW_CONFIG_PATH; echo $OPENCLAW_DATA_DIR; echo $HOME' | tee .sisyphus/evidence/task-8-env.txt
    Expected Result: prints /config/openclaw.json, /state/openclaw, /state/home
    Evidence: .sisyphus/evidence/task-8-env.txt
  ```

- [ ] 9. Tailscale sidecar (hostname non-colliding) + state PVC

  **What to do**:
  - Add `controllers.main.containers.tailscale` like current openclaw.
  - Set `TS_HOSTNAME=openclaw-nix`.
  - Mount:
    - `/dev/net/tun` hostPath
    - `/var/lib/tailscale` from dedicated PVC `openclaw-nix-tailscale-state`.

  **Recommended Agent Profile**:
  - Category: `unspecified-high`
  - Skills: `writing-nix-code`

  **Parallelization**:
  - Wave: 2
  - Blocked By: 5
  - Blocks: 10

  **References**:
  - Current sidecar: `modules/kubenix/apps/openclaw.nix:351-378`
  - Current tun+state mounts: `modules/kubenix/apps/openclaw.nix:379-395`

  **Acceptance Criteria**:
  - [ ] Rendered YAML includes tailscale container with TS_HOSTNAME=openclaw-nix.
  - [ ] New PVC name is distinct from existing openclaw.

  **QA Scenarios**:
  ```
  Scenario: Tailscale container present and state PVC name distinct
    Tool: Bash
    Steps:
      1. make manifests
      2. rg -n "name: tailscale" .k8s/apps/openclaw-nix.yaml
      3. rg -n "TS_HOSTNAME" .k8s/apps/openclaw-nix.yaml
      4. rg -n "openclaw-nix-tailscale-state" .k8s/apps/openclaw-nix.yaml
    Expected Result: all greps hit
    Evidence: .sisyphus/evidence/task-9-tailscale-render.txt
  ```

- [ ] 10. Integration: generate manifests + reconcile + smoke QA in-cluster

  **What to do**:
  - Ensure new file(s) are staged before running `make manifests` (flake uses git tree).
  - Run `make manifests` and validate outputs for `openclaw-nix`.
  - Apply via Flux workflow (commit + reconcile) or whatever is your standard; ensure existing openclaw remains running.
  - Smoke QA:
    - Pod Running, 0 initContainers
    - Workspace mount writable
    - K8s API reachable using SA token + curl

  **Recommended Agent Profile**:
  - Category: `unspecified-high`
  - Skills: `kubernetes-tools`

  **Parallelization**:
  - Wave: 3
  - Blocked By: 1-9

  **References**:
  - Flake rule: `.docs/rules.md` (new files must be `git add` before `make manifests`).

  **Acceptance Criteria**:
  - [ ] `make manifests` PASS.
  - [ ] `kubectl -n apps get pod` shows openclaw-nix Running.
  - [ ] `kubectl -n apps exec ... -- mount | rg cephfs` shows workspace mount.
  - [ ] `curl https://kubernetes.default.svc/api` succeeds from inside pod using SA token.

  **QA Scenarios**:
  ```
  Scenario: In-cluster smoke
    Tool: Bash
    Steps:
      1. make manifests |& tee .sisyphus/evidence/task-10-make-manifests.txt
      2. kubectl -n apps get deploy/openclaw openclaw-nix -o wide | tee .sisyphus/evidence/task-10-deploys.txt
      3. kubectl -n apps get pod -l app.kubernetes.io/name=openclaw-nix -o wide | tee .sisyphus/evidence/task-10-pods.txt
      4. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc 'touch /home/node/.openclaw/workspace/_probe && ls -la /home/node/.openclaw/workspace | head' | tee .sisyphus/evidence/task-10-workspace-probe.txt
      5. kubectl -n apps exec deploy/openclaw-nix -c main -- sh -lc 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt; curl -fsS --cacert $CACERT -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api | jq -r .versions[0]' | tee .sisyphus/evidence/task-10-k8s-api.txt
    Expected Result: all commands succeed; probe file created
    Evidence: .sisyphus/evidence/task-10-k8s-api.txt
  ```

---

## Final Verification Wave

- F1 (oracle): plan compliance + scope fidelity
- F2 (unspecified-high): manifest diff review + slop scan
- F3 (unspecified-high): cluster smoke QA replay + evidence capture

---

## Commit Strategy
- Keep commits atomic; ask user before pushing.

---

## Success Criteria
- `make manifests` succeeds.
- `.k8s/apps/openclaw-nix*.yaml` exists + includes Deployment/ConfigMap/Service/PVCs/RBAC.
- Pod is Running; no initContainers; workspace mounted from CephFS subPath; config patched to include whatsapp.

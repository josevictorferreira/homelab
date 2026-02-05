# OpenClaw Implementation Learnings

## [2026-02-05] Initialization
- Plan created for OpenClaw K8s installation using kubenix
- Using release submodule pattern (bjw-s app-template v4.2.0)

## [2026-02-05] Secret Resource Pattern
- Created `openclaw-config.enc.nix` following kubenix Secret pattern
- Key learnings:
  - Must include both `kubenix` and `homelab` in function parameters
  - Use `let namespace = homelab.kubernetes.namespaces.applications;` for cleaner code
  - Secret path: `kubernetes.resources.secrets.<secret-name>`
  - Use `kubenix.lib.secretsFor "key"` for SOPS secret references
  - All 4 required env vars defined: NODE_ENV, OPENCLAW_DATA_DIR, OPENCLAW_CONFIG_PATH, OPENCLAW_GATEWAY_TOKEN
- File structure validated with LSP (no errors)

## [2026-02-05] Release Submodule Implementation
- Successfully created `openclaw.nix` using release submodule pattern
- Key implementation details:
  - Must use `submodules.instances.<app-name>` structure (NOT `homelab.kubenix`)
  - Function parameters: `{ kubenix, homelab, ... }` (kubenix required for submodule pattern)
  - Namespace: Use `homelab.kubernetes.namespaces.applications` constant
  - Image format: `repository = "ghcr.io/..."; tag = "version@sha256:...";`
  - Config data: Use attrset structure (NOT toYamlStr) - release submodule handles JSON/YAML conversion
  - Ingress disabled via `values.ingress.main.enabled = false;`
  - LoadBalancer IP: Must add entry to `config/kubernetes.nix` under `loadBalancer.services`
- Generated manifest validation:
  - Deployment created with correct command, envFrom, ports
  - ConfigMap with JSON data (single-line format)
  - PVC with 10Gi, rook-ceph-block, ReadWriteOnce
  - LoadBalancer service with Cilium IPAM annotations
- LSP diagnostics: Only unused parameter warning (cosmetic)

## [2026-02-05] OpenClaw implementation complete
- Used release submodule pattern (bjw-s app-template v4.2.0)
- Image: `ghcr.io/openclaw/openclaw:latest@sha256:a02b8193...` (pinned with digest)
- Generated 2 manifests: openclaw.yaml (app resources) + openclaw-config.enc.yaml (Secret)
- Secret wired via `kubenix.lib.secretsFor "openclaw_gateway_token"` → vals → SOPS → encryption
- LoadBalancer service on port 18789 (Cilium IPAM), ingress disabled
- 10Gi PVC for persistence at /home/node/.openclaw

## [2026-02-05] Flake Git Tree Requirement
- Nix flakes ONLY see git-tracked files (`git add` required for ANY new module before build)
- `builtins.readDir` in flake context operates on filtered source tree
- Symptoms: file exists in FS but missing from `nix build` output
- Verify: `git status --porcelain` before `make manifests`

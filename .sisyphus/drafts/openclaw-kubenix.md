# Draft: OpenClaw on homelab (kubenix)

## Goal (from user)
- Install OpenClaw Kubernetes stack (from https://github.com/feiskyer/openclaw-kubernetes) into our cluster.
- Use **kubenix-only** manifests (fit homelab patterns); no direct kubectl apply / raw YAML editing.
- Use **same container images** (repos + tags) as upstream.
- Prefer using our **“submodule pattern”** for releases (pin upstream version; reproducible updates).

## Assumptions (to validate)
- Deployment is via Flux GitOps (manifests generated to `.k8s/` by `make manifests`).
- Cluster is k3s + Cilium + existing storage/ingress conventions.

## Open questions
- Which OpenClaw **image tag** should we pin (and then lock with digest)?
- Namespace preference? (upstream default vs `openclaw-system` vs something else)
- Any integrations expected: Prometheus/ServiceMonitor, Ingress, cert-manager, external DB/object store?
- Any constraints: nodeSelectors, tolerations, GPU needs, privileged pods forbidden?

## Decisions (confirmed)
- Kubenix modeling: **release submodule re-impl** (bjw-s app-template), not upstream OCI helm chart.
- Version pinning: **fixed tag** + **digest** (tag@sha256:...).
- Exposure: **LoadBalancer service** (Cilium LB IPAM). Prefer **disable ingress**.
- Secrets: **gateway token only** (`OPENCLAW_GATEWAY_TOKEN`).
- Namespace: `homelab.kubernetes.namespaces.applications`.

## Research findings
- Upstream install method: **Helm chart** (OCI) `oci://ghcr.io/feiskyer/openclaw-kubernetes/openclaw` (chart v0.1.2).
- Resources: **Namespace + 1 StatefulSet + Service + SA + ConfigMap + Secret** (+ optional Ingress/PDB/HPA). **No CRDs/webhooks/jobs.**
- Image: `ghcr.io/openclaw/openclaw` tag defaults to **`latest`** (Chart.appVersion). Init container uses same image.
- Required secret key: `OPENCLAW_GATEWAY_TOKEN` (others optional: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`).
- Required env: `NODE_ENV=production`, `OPENCLAW_DATA_DIR=/home/node/.openclaw`, `OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json`.
- ConfigMap renders `openclaw.json` from values (`gateway.port` default 18789; `logging.level` default info).
- Persistence: optional; init container seeds `/home/node/.openclaw` into PVC if empty.

## Local homelab patterns (kubenix)
- Apps live in `modules/kubenix/apps/*.nix` (auto-discovered; `_*.nix` disabled).
- Manifest pipeline: `make manifests` (gmanifests→vmanifests→umanifests→emanifests). Never edit `.k8s/*.yaml`.
- Preferred abstraction: **release submodule pattern** in `modules/kubenix/_submodules/release.nix` (bjw-s app-template v4.2.0) with `submodules.instances.<app> = { submodule = "release"; args = {...}; }`.
- Pinning convention: charts have sha256; images should be **tag@sha256:digest**.

## Proposed kubenix approach (to confirm)
- Implement OpenClaw as a kubenix app module using the **release submodule** + `args.values` to configure app-template as StatefulSet, initContainers, persistence, service, ingress.
- Secrets via SOPS+vals (`kubenix.lib.secretsFor`) into a Secret consumed via envFrom.
- Ingress: use Cilium ingressClass (`cilium`) and homelab helper(s) if applicable.

## Potential upstream mismatch (needs decision)
- `openclaw-kubernetes` chart sets image repo `ghcr.io/openclaw/openclaw` (appVersion `latest`).
- Separate upstream project `openclaw/openclaw` appears to publish image as `ghcr.io/openclaw/moltbot` with semver-ish tags (e.g. `v2026.2.3`).
- Need to decide: **strictly follow chart image** vs **follow current upstream runtime image** (if chart is stale).

## Scope boundaries (initial)
- INCLUDE: kubenix module(s) to generate all K8s resources needed for OpenClaw.
- INCLUDE: secrets wiring via existing SOPS/vals flow (no plaintext secrets).
- EXCLUDE (until asked): modifying Ceph/Rook CRs; any disruptive cluster-wide changes.

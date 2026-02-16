# Draft: Install a repository/app onto homelab k8s via Kubenix

## Original Request
- "Read this whole repository and check how we can do the same (installing it) on our k8s cluster using kubenix"

## Assumptions (unconfirmed)
- Target cluster is this repo’s homelab k3s + Flux GitOps, manifests generated via Kubenix + `make manifests`.
- “it” refers to an external app/repository the user wants deployed onto the cluster.

## What I need from user (open questions)
- Which repository/app exactly (URL)?
- Preferred install method: Helm chart, raw YAML, Operator, or “whatever upstream provides”.
- Runtime needs: namespace, ingress hostnames, TLS, persistence (PVC sizes + storage class), resources, replicas/HA.
- Secret sources: existing SOPS keys in `secrets/k8s-secrets.enc.yaml` vs new ones.
- Any constraints: must use existing ingress class/Cilium, must avoid privileged pods, etc.

## Scope Boundaries (draft)
- INCLUDE: Produce a Kubenix-based plan: Nix module(s) + secrets wiring + manifest generation + Flux reconciliation steps.
- EXCLUDE: Direct `kubectl apply` / manual cluster patching; editing `.k8s/*.yaml` by hand.

## Notes / repo rules to follow
- Never edit `.k8s/*.yaml` directly; use `make manifests` pipeline.
- Never hardcode secrets; use SOPS + `kubenix.lib.secretsFor` / `kubenix.lib.secretsInlineFor`.

## Repo Patterns Found (kubenix + gitops)
- Apps live in: `modules/kubenix/apps/` (prefix `_` disables a module)
- Rendered output lands in: `.k8s/` (notably `.k8s/apps/`) and is **generated** (don’t edit)
- Common app shape:
  - `modules/kubenix/apps/<app>.nix` (Helm/OCI chart values or raw resources)
  - `modules/kubenix/apps/<app>-config.enc.nix` (K8s Secret/Config; uses `kubenix.lib.secretsFor` / `secretsInlineFor`)
- Ingress convention: class `cilium`, TLS `wildcard-tls`, cert-manager annotations, host via `kubenix.lib.domainFor <app>`
- Storage convention:
  - Block PVCs: `storageClass = "rook-ceph-block"`, size like `20Gi`
  - Shared data: `existingClaim = <someCephFSPVC>` (CephFS)

## Make / Workflow (high level)
- Edit/add secrets: `make secrets` → updates `secrets/k8s-secrets.enc.yaml`
- Generate everything: `make manifests` (generate → inject secrets → encrypt)
- Validate: `make check` (flake), `make lint`/`make format` (nix fmt)
- GitOps apply: commit/push → Flux sync; manual nudge: `make reconcile`

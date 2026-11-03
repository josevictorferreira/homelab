---
name: "kubenix-code"
description: "Write, review, and modify Kubenix Kubernetes manifests in Nix for the homelab. Use when authoring new app modules in modules/kubenix/apps/, configuring deployments, services, probes, ingresses, or decommissioning services."
---

# Kubenix Code

Use this skill when writing, reviewing, or modifying Kubenix modules in this homelab repository.

## Module Pattern

Files in `modules/kubenix/apps/<app>.nix` are evaluated by `modules/kubenix/default.nix` with `{ homelab, kubenix, ... }`:

```nix
{ homelab, ... }:
let
  name = "example";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/org/image:1.0.0@sha256:...";
  port = 8080;
in
{
  kubernetes.resources.deployments.${name} = {
    metadata = { inherit name namespace; };
    spec = {
      replicas = 1;
      selector.matchLabels.app = name;
      template = {
        metadata.labels.app = name;
        spec.containers.${name} = {
          inherit image;
          ports = [{ inherit name; containerPort = port; }];
          resources = {
            requests = { cpu = "100m"; memory = "128Mi"; };
            limits = { cpu = "500m"; memory = "512Mi"; };
          };
        };
      };
    };
  };

  kubernetes.resources.services.${name} = {
    metadata = { inherit name namespace; };
    spec = {
      type = "ClusterIP";
      selector.app = name;
      ports = [{ inherit name port; targetPort = port; }];
    };
  };
}
```

---

## Gotchas & Rules

### 1. Stage New Files in Git Before `make manifests`
- **Rule**: Run `git add modules/kubenix/...` before running `make manifests` or `make check`.
- **Why**: Nix flakes evaluate against git state. Untracked/unstaged files are completely invisible to `nix build .#gen-manifests`, causing silent omissions or build failures (discovered during Grimmory and Paperclip onboarding).
- **Verify**: `git status --porcelain modules/kubenix/` shows files staged (`A`), then `make manifests`.

### 2. Prefer Raw `kubernetes.resources` for Internal/ClusterIP Services
- **Rule**: Use raw `kubernetes.resources` (patterned after `flaresolverr.nix` or `camofox.nix`) instead of `submodules.packages.release` for internal services.
- **Why**: `submodules.packages.release` (bjw-s app-template wrapper) eagerly calls `kubenix.lib.serviceAnnotationFor`, which crashes Nix evaluation if `homelab.kubernetes.loadBalancer.services.<name>` is omitted from `config/kubernetes.nix`—even for ClusterIP. Disabling persistence on the submodule also fails schema validation unless full dummy fields (`type`, `storageClass`) are supplied.
- **Verify**: `make manifests` generates clean Deployment and Service YAML without schema errors.

### 3. Explicitly Pin `{APP}_PORT` to Shadow Injected Service Env Vars
- **Rule**: If the container listens on port `$FOO_PORT`, set `env = [{ name = "FOO_PORT"; value = toString port; }]`.
- **Why**: Kubernetes automatically injects `{SERVICE_NAME}_PORT=tcp://<svc-ip>:<port>` into pods from Services with matching names. Applications (Node.js, Python, Gunicorn, Granian) that parse this variable as an integer port crash on boot with `ERR_SOCKET_BAD_PORT` (NaN) or `invalid integer` (commit `c3e2b6fa` on Camofox; Searxng).
- **Verify**: `kubectl get deploy <name> -n apps -o jsonpath='{.spec.template.spec.containers[0].env}'` contains explicit integer port string.

### 4. Add Explicit `Host` Header to Probes for Hostname-Guarded Apps
- **Rule**: Add `httpHeaders = [{ name = "Host"; value = kubenix.lib.domainFor app; }];` to `httpGet` probes when apps enforce hostname allowlists.
- **Why**: Kubelet HTTP probes default to `Host: <pod-ip>`. Apps enforcing hostname validation or CSRF guards (e.g. Paperclip, OpenClaw Control UI) reject `<pod-ip>` with HTTP 403 Forbidden, causing probe failure and CrashLoopBackOff (commit `030e9382`).
- **Verify**: `kubectl describe pod <pod> -n apps` shows probes succeeding (200 OK) instead of 403.

### 5. Set Explicit Limits on Init Containers and Sidecars
- **Rule**: Never leave `resources.limits` undefined on init containers or sidecars.
- **Why**: Containers in the `apps` namespace without explicit limits inherit the `LimitRange` default of 2 CPUs. Two init containers or sidecars without limits will request 4 CPUs, instantly exceeding the namespace ResourceQuota and failing pod scheduling.
- **Verify**: `kubectl describe pod <name> -n apps | grep -A2 "Limits:"` shows bounded values (e.g. `100m` cpu, `128Mi` memory).

### 6. Set `supplementalGroups = [ 2002 ];` for Shared CephFS Mounts
- **Rule**: If mounting `/shared/*` (`shared-storage` PVC), add `spec.template.spec.securityContext.supplementalGroups = [ 2002 ];`.
- **Why**: Shared CephFS scratch storage is unified under GID 2002 (`homelab`). Container processes running with other primary GIDs cannot write to shared directories without group 2002 membership.
- **Verify**: `kubectl exec deploy/<name> -n apps -c <container> -- id` shows `groups=...2002`.

### 7. Full Manifest Pipeline & Git Commit Required
- **Rule**: Never edit `.k8s/*.yaml` directly. Run `make manifests`. Commit BOTH `.nix` and generated `.k8s/` files before expecting Flux to deploy.
- **Why**: Flux reconciles the cluster strictly from the git repository's `.k8s/` directory. Running `kubectl apply` locally will be overwritten by Flux, and uncommitted `.k8s/` files will never be applied to the cluster.
- **Verify**: `git status` shows `.k8s/` manifests matching `.nix` changes; `git diff --cached` clean before push.

### 8. Decommission Apps by Prefixing `_` AND Running `git rm`
- **Rule**: To disable or delete an app, rename `modules/kubenix/apps/<app>.nix` to `_<app>.nix` (and `_<app>-config.enc.nix`), run `make manifests`, and explicitly `git rm .k8s/apps/<app>.yaml`.
- **Why**: The kubenix loader ignores files starting with `_`, but `make manifests` does not delete existing `.k8s/` files. Unless `git rm .k8s/apps/<app>.yaml` is executed, Flux keeps applying the stale manifest from git (commits `101fe2da` for Paperclip, `299761e0` for Valoris).
- **Verify**: `git ls-files .k8s/apps/<app>.yaml` returns empty.

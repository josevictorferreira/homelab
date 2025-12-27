# Kubernetes Manifest Generation Refactoring Plan

## Objective

Reorganize the Kubernetes manifest generation structure to:
1. Move generated manifests from `kubernetes/manifests` to `.k8s-manifests` (root level)
2. Move kubenix modules from `kubernetes/kubenix` to `modules/kubenix`
3. Maintain full compatibility with FluxCD and existing workflows

## Current Structure

```
homelab/
├── kubernetes/
│   ├── kubenix/              # Nix modules for manifest generation
│   │   ├── default.nix       # Main renderer module
│   │   ├── _base.nix
│   │   ├── _crds.nix
│   │   ├── _lib/
│   │   ├── _submodules/
│   │   ├── apps/
│   │   ├── bootstrap/
│   │   ├── monitoring/
│   │   ├── storage/
│   │   └── system/
│   └── manifests/            # Generated YAML manifests (FluxCD reads from here)
│       ├── flux-system/      # FluxCD bootstrap (manually managed)
│       ├── apps/
│       ├── bootstrap/
│       ├── monitoring/
│       ├── storage/
│       └── system/
└── flake.nix                 # References kubernetes/kubenix
```

## Target Structure

```
homelab/
├── .k8s-manifests/           # Generated YAML manifests (versioned)
│   ├── flux-system/          # FluxCD bootstrap (manually managed)
│   ├── apps/
│   ├── bootstrap/
│   ├── monitoring/
│   ├── storage/
│   └── system/
├── modules/
│   └── kubenix/              # Nix modules for manifest generation
│       ├── default.nix
│       ├── _base.nix
│       ├── _crds.nix
│       ├── _lib/
│       ├── _submodules/
│       ├── apps/
│       ├── bootstrap/
│       ├── monitoring/
│       ├── storage/
│       └── system/
└── flake.nix                 # Updated to reference modules/kubenix
```

## Files to Modify

### 1. `flake.nix`

**Change:**
```nix
# FROM:
kubenixModule = import ./kubernetes/kubenix { ... };

# TO:
kubenixModule = import ./modules/kubenix { ... };
```

### 2. `Makefile`

**Changes:**
```makefile
# FROM:
MANIFESTS_DIR ?= kubernetes/manifests

# TO:
MANIFESTS_DIR ?= .k8s-manifests
```

Update all hardcoded paths in targets:
- `vmanifests`: Change `find kubernetes/manifests` → `find .k8s-manifests`
- `emanifests`: Change `find kubernetes/manifests` → `find .k8s-manifests`
- `gmanifests`: Change all `kubernetes/manifests` references → `.k8s-manifests`

### 3. FluxCD Sync Configuration

**File:** `.k8s-manifests/flux-system/gotk-sync.yaml`

```yaml
# FROM:
spec:
  path: ./kubernetes/manifests

# TO:
spec:
  path: ./.k8s-manifests
```

### 4. `.sops.yaml` (if exists)

Check if there are path-specific encryption rules that reference `kubernetes/manifests` and update them to `.k8s-manifests`.

## Migration Steps

### Phase 1: Prepare New Structure

1. Create `modules/kubenix` directory
2. Copy contents from `kubernetes/kubenix` to `modules/kubenix`
3. Create `.k8s-manifests` directory
4. Copy contents from `kubernetes/manifests` to `.k8s-manifests`

### Phase 2: Update Configuration Files

5. Update `flake.nix` to reference `modules/kubenix`
6. Update `Makefile` with new paths
7. Update `.k8s-manifests/flux-system/gotk-sync.yaml` with new path
8. Update `.sops.yaml` if needed

### Phase 3: Verify and Test

9. Run `nix flake check` to verify flake is valid
10. Run `make gmanifests` to verify manifest generation works
11. Run `make vmanifests` to verify secret substitution works
12. Run `make emanifests` to verify encryption works
13. Verify FluxCD can reconcile with new paths (may need to push and trigger)

### Phase 4: Cleanup

14. Remove old `kubernetes/kubenix` directory
15. Remove old `kubernetes/manifests` directory
16. Remove empty `kubernetes` directory
17. Commit all changes

## Rollback Plan

If issues arise:
1. Revert FluxCD path change first (most critical)
2. Restore `kubernetes/manifests` from `.k8s-manifests`
3. Restore `kubernetes/kubenix` from `modules/kubenix`
4. Revert `flake.nix` and `Makefile` changes

## FluxCD Considerations

- **Critical:** The `gotk-sync.yaml` change must be committed and pushed BEFORE FluxCD tries to reconcile
- FluxCD will look for the new path in the repository, so the manifests must exist at `.k8s-manifests` in the main branch
- The `flux-system` folder should be moved as-is to preserve the FluxCD bootstrap configuration
- After the change, run `flux reconcile kustomization flux-system -n flux-system --with-source` to verify

## Order of Operations (Atomic Approach)

To avoid breaking the workflow, perform all changes in a single commit:

1. Copy (don't move) `kubernetes/kubenix` → `modules/kubenix`
2. Copy (don't move) `kubernetes/manifests` → `.k8s-manifests`
3. Update all configuration files (`flake.nix`, `Makefile`, `gotk-sync.yaml`)
4. Test locally with `make gmanifests` (should write to `.k8s-manifests`)
5. Commit ALL changes including both old and new directories
6. Push to main branch
7. Verify FluxCD reconciles successfully with `flux events --watch`
8. Once verified, create a cleanup commit to remove old `kubernetes/` directory

## Verification Checklist

- [ ] `nix flake check` passes
- [ ] `make gmanifests` generates manifests to `.k8s-manifests/`
- [ ] `make vmanifests` processes secrets correctly
- [ ] `make emanifests` encrypts files correctly
- [ ] `make manifests` runs the full pipeline
- [ ] FluxCD reconciles successfully after push
- [ ] All Kubernetes resources remain healthy after reconciliation

---

## Implementation Todo List

### Phase 1: Prepare New Structure

- [x] 1.1 Create `modules/kubenix` directory
  ```bash
  mkdir -p modules/kubenix
  ```

- [x] 1.2 Copy kubenix modules to new location
  ```bash
  cp -r kubernetes/kubenix/* modules/kubenix/
  ```

- [x] 1.3 Create `.k8s-manifests` directory
  ```bash
  mkdir -p .k8s-manifests
  ```

- [x] 1.4 Copy manifests to new location
  ```bash
  cp -r kubernetes/manifests/* .k8s-manifests/
  ```

### Phase 2: Update Configuration Files

- [x] 2.1 Update `flake.nix`
  - Change `./kubernetes/kubenix` to `./modules/kubenix`

- [x] 2.2 Update `Makefile` - MANIFESTS_DIR variable
  - Change `MANIFESTS_DIR ?= kubernetes/manifests` to `MANIFESTS_DIR ?= .k8s-manifests`

- [x] 2.3 Update `Makefile` - vmanifests target
  - Change `find kubernetes/manifests` to `find .k8s-manifests`

- [x] 2.4 Update `Makefile` - emanifests target
  - Change `find kubernetes/manifests` to `find .k8s-manifests`

- [x] 2.5 Update `Makefile` - gmanifests target
  - Change all `kubernetes/manifests` references to `.k8s-manifests`

- [x] 2.6 Update `.k8s-manifests/flux-system/gotk-sync.yaml`
  - Change `path: ./kubernetes/manifests` to `path: ./.k8s-manifests`

- [x] 2.7 Check and update `.sops.yaml` if it contains path references
  - Update any `kubernetes/manifests` paths to `.k8s-manifests`

### Phase 3: Verify and Test Locally

- [x] 3.1 Run `nix flake check` to verify flake syntax is valid

- [x] 3.2 Run `make gmanifests` to verify manifest generation
  - Confirm output goes to `.k8s-manifests/`

- [x] 3.3 Run `make vmanifests` to verify secret substitution works

- [x] 3.4 Run `make emanifests` to verify encryption works

- [x] 3.5 Run `make manifests` to verify full pipeline

- [x] 3.6 Run `make lint` to ensure code formatting is correct

### Phase 4: Commit and Deploy

- [ ] 4.1 Stage all changes (both old and new directories)
  ```bash
  git add modules/kubenix .k8s-manifests flake.nix Makefile
  ```

- [ ] 4.2 Create migration commit with both structures
  ```bash
  git commit -m "refactor: migrate kubernetes manifests to .k8s-manifests and kubenix to modules/kubenix"
  ```

- [ ] 4.3 Push to main branch
  ```bash
  git push origin main
  ```

- [ ] 4.4 Monitor FluxCD reconciliation
  ```bash
  flux events --watch
  ```

- [ ] 4.5 Verify FluxCD reconciles successfully
  ```bash
  flux reconcile kustomization flux-system -n flux-system --with-source
  ```

- [ ] 4.6 Verify all Kubernetes resources are healthy
  ```bash
  kubectl get all -A
  ```

### Phase 5: Cleanup

- [ ] 5.1 Remove old `kubernetes/kubenix` directory
  ```bash
  rm -rf kubernetes/kubenix
  ```

- [ ] 5.2 Remove old `kubernetes/manifests` directory
  ```bash
  rm -rf kubernetes/manifests
  ```

- [ ] 5.3 Remove empty `kubernetes` directory
  ```bash
  rmdir kubernetes
  ```

- [ ] 5.4 Commit cleanup changes
  ```bash
  git add -A
  git commit -m "chore: remove old kubernetes directory after migration"
  ```

- [ ] 5.5 Push cleanup commit
  ```bash
  git push origin main
  ```

- [ ] 5.6 Final verification - ensure FluxCD still reconciles correctly
  ```bash
  flux reconcile kustomization flux-system -n flux-system --with-source
  ```

### Rollback (If Needed)

- [ ] R.1 If FluxCD fails after push, immediately revert the `gotk-sync.yaml` path change
- [ ] R.2 Restore old paths in `flake.nix` and `Makefile`
- [ ] R.3 Force push the revert to main
- [ ] R.4 Investigate the issue before attempting migration again

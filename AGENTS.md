# AGENTS.md - AI Agent Guidelines for Homelab

## CRITICAL: Data Loss Prevention Rules

### NEVER Do These Without Explicit User Confirmation

1. **NEVER remove finalizers from Ceph CRDs** (CephCluster, CephFilesystem, CephBlockPool, CephObjectStore)
   - Removing finalizers allows deletion which DESTROYS ALL DATA in that resource
   - Even if the resource is "stuck", the finalizer exists to protect data
   - ALWAYS ask: "This will permanently delete all data in [resource]. Are you sure?"

2. **NEVER delete or allow deletion of**:
   - CephCluster - destroys ALL storage data
   - CephFilesystem - destroys ALL CephFS data
   - CephBlockPool - destroys ALL block storage data
   - Rook-ceph namespace - destroys EVERYTHING

3. **NEVER assume Flux recreation is safe**
   - When Flux recreates a Ceph resource, it creates a NEW empty one
   - The old data is NOT migrated - it's GONE
   - Deleting a Ceph CR = deleting the underlying data

### Before Any Ceph Operation

1. **Check data pool usage first**:
   ```bash
   kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph df
   ```
   If pools have significant data, STOP and confirm with user.

2. **Check for existing snapshots**:
   ```bash
   # RBD snapshots
   kubectl exec -n rook-ceph deploy/rook-ceph-tools -- bash -c 'for img in $(rbd ls replicapool); do rbd snap ls replicapool/$img; done'
   
   # CephFS snapshots
   kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph fs subvolume snapshot ls <fs-name> <subvol> --group_name=<group>
   ```

3. **Verify what will be affected**:
   ```bash
   kubectl get pv -o custom-columns='NAME:.metadata.name,STORAGE-CLASS:.spec.storageClassName,CLAIM:.spec.claimRef.name'
   ```

### Safe Ceph Troubleshooting Patterns

**When CephCluster is stuck:**
- DO: Wait for OSDs to recover
- DO: Check `ceph health detail` for specific issues
- DO: Fix underlying issues (disk space, network, etc.)
- DON'T: Remove finalizers
- DON'T: Delete and recreate the CephCluster

**When OSD prepare jobs hang:**
- DO: Add deviceFilter to exclude problematic devices
- DO: Blacklist kernel modules (nbd, rbd if needed)
- DO: Reboot nodes if processes are in D-state
- DON'T: Delete the CephCluster

**When CephFilesystem has issues:**
- DO: Check MDS status and logs
- DO: Check subvolume health
- DON'T: Delete the CephFilesystem CR

## Incident Record

### 2026-01-27: CephFS Data Loss

**What happened:**
- CephCluster was stuck with deletionTimestamp
- Finalizer was removed to "fix" the stuck state
- This allowed CephCluster deletion, which cascaded to CephFilesystem recreation
- CephFilesystem recreation wiped the data pool (ceph-filesystem-data0)
- All CephFS shared storage data (downloads, images, root) was permanently lost

**Data lost:**
- /volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17/*

**Data preserved:**
- Block storage (replicapool): 63 GiB - intact
- Object storage (rgw.buckets.data): 7.3 GiB - intact
- RBD snapshots from Sep-Oct 2025 - intact

**Root cause:**
Removing finalizer from CephCluster allowed Flux to delete and recreate it, which recreated the CephFilesystem with empty data pools.

**Prevention:**
- NEVER remove Ceph finalizers without understanding the data loss implications
- ALWAYS check `ceph df` before any destructive Ceph operation
- Treat Ceph CRD deletion as equivalent to `rm -rf` on all data

## General Guidelines

### GitOps Workflow (Flux)

1. All changes go through: Nix config -> generate manifests -> encrypt secrets -> commit -> push -> Flux sync
2. NEVER apply manifests directly with kubectl (except for debugging)
3. NEVER commit unencrypted secrets to .k8s/
4. Use `make manifests` which handles encryption via SOPS

### Before Pushing Changes

1. Run `make manifests` (not `make gmanifests`)
2. Verify no secrets are exposed: `grep -r "kind: Secret" .k8s/*.yaml` (should only find .enc.yaml files)
3. Review `git diff` for unexpected changes

### PV/PVC Management

- PVs are immutable - changing paths requires delete and recreate
- Always delete both PV and PVC together, then let Flux recreate
- For CephFS static volumes, claimRef must be cleared after PV recreation

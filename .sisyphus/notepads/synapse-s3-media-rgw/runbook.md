# Synapse S3 Media Storage Runbook

## Overview

Synapse uses the `synapse-s3-storage-provider` to store media in Ceph RGW (S3-compatible). This runbook covers outage response, weekly maintenance, and known limitations.

**Key Configuration:**
- Bucket: `matrix-synapse-media`
- Endpoint: `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local`
- Media path: `/data/media_store`
- Namespace: `apps`
- Deployment: `synapse-matrix-synapse`

---

## Outage Response (RGW/S3 Down)

### Target Behavior

**Serve existing + accept new** - Synapse continues operating normally during S3 outages.

### How It Works

**Reads:**
- Local cache is checked first
- If file exists locally, it is served immediately (no S3 dependency)
- If file is missing locally and S3 is down, the read may fail with 5xx
- Existing local cache continues serving regardless of S3 state

**Writes:**
- New uploads are accepted and stored locally
- Async S3 upload is queued
- When RGW returns, queued uploads resume automatically
- No data loss for new uploads during outages

### Symptoms

```
# S3 provider logs show connection errors
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -i s3

# Expected patterns during outage:
# - "Connection refused" or "No route to host"
# - "Failed to upload file to S3"
# - "Retrying upload..."
```

### Diagnostic Commands

```bash
# Check S3 connectivity from Synapse pod
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- \
  python -c 'import boto3; s3 = boto3.client("s3", endpoint_url="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"); print(s3.list_buckets())'

# Check RGW pod status
kubectl get pods -n rook-ceph -l app=rook-ceph-rgw

# Check provider logs for S3 errors
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -iE "s3|boto|upload|storage" | tail -50

# Check local media store disk usage
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- du -sh /data/media_store

# List local media directories
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- ls -la /data/media_store/
```

### Monitoring: Backlog Growing Indicators

```bash
# Check for growing number of files in local_content (not yet uploaded)
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- \
  find /data/media_store/local_content -type f | wc -l

# Check disk usage trend (run twice, 5 minutes apart)
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- du -sh /data/media_store

# Log grep patterns for backlog issues
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -iE "queue|backlog|pending|retry"
```

### Recovery

**No action required.** Synapse continues serving from local storage. S3 uploads resume automatically when RGW returns.

If RGW is down for extended periods:
1. Monitor local disk usage on the PVC
2. If disk approaches full, consider temporary PVC expansion
3. Once RGW returns, uploads will resume automatically

---

## Weekly Maintenance (Sync + Prune)

### Prerequisites

```bash
# Confirm OBC secret exists
kubectl get secret -n apps matrix-synapse-media

# Verify secret has required keys
kubectl get secret -n apps matrix-synapse-media -o jsonpath='{.data}' | jq 'keys'

# Expected: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

### Procedure

#### Step 1: Create Temp Sync Pod

```bash
# Run a temporary pod with media store access
kubectl run synapse-media-sync --rm -i --restart=Never \
  --namespace apps \
  --image ghcr.io/element-hq/synapse:v1.146.0 \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "sync",
        "image": "ghcr.io/element-hq/synapse:v1.146.0",
        "command": ["sh", "-c", "sleep 3600"],
        "volumeMounts": [
          {"name": "media", "mountPath": "/data/media_store"},
          {"name": "modules", "mountPath": "/modules"}
        ],
        "envFrom": [{"secretRef": {"name": "matrix-synapse-media"}}],
        "env": [
          {"name": "PYTHONPATH", "value": "/modules"},
          {"name": "AWS_CONFIG_FILE", "value": "/modules/aws-config"},
          {"name": "AWS_EC2_METADATA_DISABLED", "value": "true"}
        ]
      }],
      "volumes": [
        {"name": "media", "persistentVolumeClaim": {"claimName": "synapse-matrix-synapse"}},
        {"name": "modules", "emptyDir": {}}
      ]
    }
  }'
```

#### Step 2: Install Provider and Configure

Inside the temp pod:

```bash
# Install the S3 storage provider
pip install --no-cache-dir --target /modules synapse-s3-storage-provider

# Create AWS config for path-style addressing (required for RGW)
mkdir -p /modules
cat > /modules/aws-config << 'EOF'
[default]
s3 =
  addressing_style = path
EOF
```

#### Step 3: Update Media Records

```bash
# Update the cache database with files not accessed in 30 days
python -m s3_storage_provider.s3_media_upload update /data/media_store 30d
```

**Expected output:**
```
Syncing files that haven't been accessed since: <date>
Synced X new rows
<progress bar>
Updated Y as deleted
```

#### Step 4: Upload to S3 (Without Delete First)

```bash
# Upload files to S3 (dry-run, no delete)
python -m s3_storage_provider.s3_media_upload upload /data/media_store matrix-synapse-media
```

**Verify upload success:**
- Exit code should be 0
- Log should show "Uploaded X files" or similar
- No errors in output

#### Step 5: Verify Objects in S3

```bash
# Verify objects exist in S3 (from the temp pod)
python -c "
import boto3
s3 = boto3.client('s3', endpoint_url='http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local')
response = s3.list_objects_v2(Bucket='matrix-synapse-media', Prefix='synapse/', MaxKeys=10)
print(f\"Found {response.get('KeyCount', 0)} objects in S3\")
for obj in response.get('Contents', []):
    print(f\"  - {obj['Key']} ({obj['Size']} bytes)\")
"
```

#### Step 6: Upload with Delete

**Only after confirming objects exist in S3:**

```bash
# Upload and delete local files that are safely in S3
python -m s3_storage_provider.s3_media_upload upload /data/media_store matrix-synapse-media --delete
```

#### Step 7: Prune Old Local Files

```bash
# Find files older than 30 days (that weren't caught by upload --delete)
find /data/media_store -type f -mtime +30 | head -20

# Count how many would be deleted
find /data/media_store -type f -mtime +30 | wc -l

# Delete only after confirming in S3 and verifying upload success
find /data/media_store -type f -mtime +30 -delete
```

#### Step 8: Cleanup

```bash
# Exit the temp pod (it will be deleted automatically due to --rm)
exit
```

---

## Rollback Procedure

If S3 migration fails or needs to be reverted:

```bash
# 1. Edit the matrix.nix to remove media_storage_providers from extraConfig
# 2. Regenerate manifests
make manifests

# 3. Wait for Flux to apply or force reconcile
make reconcile

# 4. Synapse will now serve media from local PVC only
# Previously uploaded S3 media will need to be re-downloaded or restored from backup
```

---

## Known Limitations and Risks

### Runtime pip Install Depends on PyPI

**Risk:** The provider is installed via `pip install` at container startup using an `emptyDir` volume. If PyPI is unavailable during a pod restart, the container will fail to start.

**Mitigation:**
- Container restart will retry pip install
- Consider pre-building a custom Synapse image with the provider baked in for production

**Evidence in logs:**
```
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -i "pip\|install\|synapse-s3-storage-provider"
```

### No Local Cache for S3 Objects

**Behavior:** Remote media (from other servers) is always fetched from S3. There is no local caching layer for S3 objects.

**Impact:** Higher latency for remote media if S3 is slow or distant.

### PVC Size Monitoring

During extended S3 outages, local media accumulates. Monitor PVC usage:

```bash
# Check current usage
kubectl get pvc -n apps synapse-matrix-synapse -o jsonpath='{.status.capacity.storage}'

# Check actual usage
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- df -h /data/media_store
```

---

## Quick Reference Commands

```bash
# Check S3 provider is loaded
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -i "s3_storage_provider\|S3StorageProvider"

# Check recent S3 operations
kubectl logs -n apps deploy/synapse-matrix-synapse -c synapse | grep -iE "upload|download|s3" | tail -20

# Check local media count
kubectl exec -n apps deploy/synapse-matrix-synapse -c synapse -- find /data/media_store -type f | wc -l

# Check S3 bucket object count (from temp pod)
python -c "import boto3; s3 = boto3.client('s3', endpoint_url='http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local'); print(sum(1 for _ in s3.list_objects_v2(Bucket='matrix-synapse-media', Prefix='synapse/').get('Contents', [])))"
```
#KM|
#VM|## Task 1 Findings
#HW|
#QW|- Chart v3.12.19 supports:
#TK|  - synapse.extraCommands: pip install synapse-s3-storage-provider
#HZ|  - synapse.extraEnv / extraSecrets for AWS keys if needed
#XY|  - synapse.extraVolumes / extraVolumeMounts: already used for bridges
#XW|
#RN|- Synapse pod ns=apps, name=synapse-matrix-synapse-* (hash)
#SK|
#YM|- Media store: /data/media_store (persistence default)
#HK|  - local_content, remote_content subdirs
#NK|  - Exec failed (distroless?)
#BY|
#VR|- OBC secrets pattern: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (open-webui, backups etc.)
#VP|
#PH|- S3 provider config:
#VH|  media_storage_providers:
#TY|  - module: s3_storage_provider.S3StorageProviderBackend
#ZP|    store_local: true
#JR|    store_remote: true
#RZ|    config:
#HR|      bucket: ...
#VR|      endpoint_url: ...
#QK|      # access_key_id etc optional if IAM/env
#HK|
#KM|## Task 3: Runtime pip install for synapse-s3-storage-provider
#VM|
#QW|- **Completed:** Added runtime pip install via synapse.extraCommands + shared volume + PYTHONPATH
#TK|
#HZ|### Changes to modules/kubenix/apps/matrix.nix
#XY|
#XW|- extraCommands (runs at container startup):
#RN|  - mkdir -p /modules
#SK|  - Creates /modules/aws-config with RGW path-style addressing
#YM|  - pip install --no-cache-dir --target /modules synapse-s3-storage-provider
#HK|
#NK|- extraVolumes: Added synapse-python-modules emptyDir volume
#BY|
#VR|- extraVolumeMounts: Mounted synapse-python-modules at /modules
#VP|
#PH|- extraEnv:
#VH|  - PYTHONPATH=/n-  - AWS_CONFIG_FILE=/modules/aws-config
#TY|  - AWS_EC2_METADATA_DISABLED=true
#ZP|
#JR|### Chart Behavior
#RZ|- The matrix-synapse chart v3.12.19 appends extraCommands to the container startup script
#HR|- Commands run before synapse starts, ensuring provider is installed
#VR|- EmptyDir volume persists across container restarts within the same pod
#QK|
#HK|### Generated Manifest Verification
#KM|- Deployment includes pip install in command script
#VM|- Volume and mounts correctly configured
#QW|- Environment variables present in container spec

## Task 4 Findings: Configure media_storage_providers

### S3 Storage Provider Config Structure

The `media_storage_providers` config must be a list of provider objects:

```nix
media_storage_providers = [
  {
    module = "s3_storage_provider.S3StorageProviderBackend";
    store_local = true;
    store_remote = true;
    store_synchronous = false;
    config = {
      bucket = bucketName;
      endpoint_url = kubenix.lib.objectStoreEndpoint;
      region_name = "us-east-1";
      prefix = "synapse/";
      request_checksum_calculation = "when_required";
      response_checksum_validation = "when_required";
    };
  }
];
```

### RGW Compatibility Settings

For Ceph RGW compatibility, these settings are REQUIRED:
- `request_checksum_calculation: "when_required"` - Disables automatic checksum
- `response_checksum_validation: "when_required"` - Disables checksum validation
- Path-style addressing via AWS_CONFIG_FILE: `addressing_style = path`

### AWS Credentials from OBC Secret

Credentials are loaded via environment variables using `valueFrom.secretKeyRef`:

```nix
{
  name = "AWS_ACCESS_KEY_ID";
  valueFrom = {
    secretKeyRef = {
      name = bucketName;  # "matrix-synapse-media"
      key = "AWS_ACCESS_KEY_ID";
    };
  };
}
```

The OBC secret name matches the bucket name (`matrix-synapse-media`).

### Key Lessons

1. **Flakes use git state**: Must `git add` files before `make manifests` picks up changes
2. **Nix list syntax**: List elements separated by whitespace/newlines, no commas needed
3. **Edit carefully**: When using `edit` tool with replace, ensure no duplicate entries remain
4. **Verify generated YAML**: Always check `.k8s/apps/matrix.yaml` for expected config


---

## Historical Learnings

#VM|## Task 1 Findings
#HW|
#QW|- Chart v3.12.19 supports:
#TK|  - synapse.extraCommands: pip install synapse-s3-storage-provider
#HZ|  - synapse.extraEnv / extraSecrets for AWS keys if needed
#XY|  - synapse.extraVolumes / extraVolumeMounts: already used for bridges
#XW|
#RN|- Synapse pod ns=apps, name=synapse-matrix-synapse-* (hash)
#SK|
#YM|- Media store: /data/media_store (persistence default)
#HK|  - local_content, remote_content subdirs
#NK|  - Exec failed (distroless?)
#BY|
#VR|- OBC secrets pattern: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (open-webui, backups etc.)
#VP|
#PH|- S3 provider config:
#VH|  media_storage_providers:
#TY|  - module: s3_storage_provider.S3StorageProviderBackend
#ZP|    store_local: true
#JR|    store_remote: true
#RZ|    config:
#HR|      bucket: ...
#VR|      endpoint_url: ...
#QK|      # access_key_id etc optional if IAM/env
#HK|
#KM|## Task 3: Runtime pip install for synapse-s3-storage-provider
#VM|
#QW|- **Completed:** Added runtime pip install via synapse.extraCommands + shared volume + PYTHONPATH
#TK|
#HZ|### Changes to modules/kubenix/apps/matrix.nix
#XY|
#XW|- extraCommands (runs at container startup):
#RN|  - mkdir -p /modules
#SK|  - Creates /modules/aws-config with RGW path-style addressing
#YM|  - pip install --no-cache-dir --target /modules synapse-s3-storage-provider
#HK|
#NK|- extraVolumes: Added synapse-python-modules emptyDir volume
#BY|
#VR|- extraVolumeMounts: Mounted synapse-python-modules at /modules
#VP|
#PH|- extraEnv:
#VH|  - PYTHONPATH=/n-  - AWS_CONFIG_FILE=/modules/aws-config
#TY|  - AWS_EC2_METADATA_DISABLED=true
#ZP|
#JR|### Chart Behavior
#RZ|- The matrix-synapse chart v3.12.19 appends extraCommands to the container startup script
#HR|- Commands run before synapse starts, ensuring provider is installed
#VR|- EmptyDir volume persists across container restarts within the same pod
#QK|
#HK|### Generated Manifest Verification
#KM|- Deployment includes pip install in command script
#VM|- Volume and mounts correctly configured
#QW|- Environment variables present in container spec

## Task 4 Findings: Configure media_storage_providers

### S3 Storage Provider Config Structure

The `media_storage_providers` config must be a list of provider objects:

```nix
media_storage_providers = [
  {
    module = "s3_storage_provider.S3StorageProviderBackend";
    store_local = true;
    store_remote = true;
    store_synchronous = false;
    config = {
      bucket = bucketName;
      endpoint_url = kubenix.lib.objectStoreEndpoint;
      region_name = "us-east-1";
      prefix = "synapse/";
      request_checksum_calculation = "when_required";
      response_checksum_validation = "when_required";
    };
  }
];
```

### RGW Compatibility Settings

For Ceph RGW compatibility, these settings are REQUIRED:
- `request_checksum_calculation: "when_required"` - Disables automatic checksum
- `response_checksum_validation: "when_required"` - Disables checksum validation
- Path-style addressing via AWS_CONFIG_FILE: `addressing_style = path`

### AWS Credentials from OBC Secret

Credentials are loaded via environment variables using `valueFrom.secretKeyRef`:

```nix
{
  name = "AWS_ACCESS_KEY_ID";
  valueFrom = {
    secretKeyRef = {
      name = bucketName;  # "matrix-synapse-media"
      key = "AWS_ACCESS_KEY_ID";
    };
  };
}
```

The OBC secret name matches the bucket name (`matrix-synapse-media`).

### Key Lessons

1. **Flakes use git state**: Must `git add` files before `make manifests` picks up changes
2. **Nix list syntax**: List elements separated by whitespace/newlines, no commas needed
3. **Edit carefully**: When using `edit` tool with replace, ensure no duplicate entries remain
4. **Verify generated YAML**: Always check `.k8s/apps/matrix.yaml` for expected config


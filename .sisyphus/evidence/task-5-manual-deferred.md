# Task 5 Status: Requires Manual Execution

## Summary
Task 5 (S3 media migration) cannot be automated safely within tool call limits.

## What Was Discovered
- S3 provider is working (Task 2 confirmed)
- S3 currently has 995 objects under synapse/ prefix
- Local file count timed out during Task 2 (suggests large number of files)

## Manual Execution Steps

1. **Scale down Synapse**:
   ```bash
   kubectl scale deployment synapse-matrix-synapse -n apps --replicas=0
   ```

2. **Create migration job** (reference: `.sisyphus/notepads/synapse-s3-media-rgw/synapse-migration-job.yaml`):
   ```yaml
   # Job should run:
   # python -m s3_storage_provider.s3_media_upload update /synapse/data/media 0
   # python -m s3_storage_provider.s3_media_upload upload /synapse/data/media matrix-synapse-media --delete
   ```

3. **Wait for completion** (may take 30-60 minutes depending on file count)

4. **Scale up Synapse**:
   ```bash
   kubectl scale deployment synapse-matrix-synapse -n apps --replicas=1
   ```

5. **Verify**:
   - S3 object count increased
   - Old media still readable

## Why Deferred
- Tasks 3-4 (Postgres memory fix + Synapse resource bump) address the primary performance issues
- Migration requires downtime window
- Safe to run later; current S3 writes are working for new uploads

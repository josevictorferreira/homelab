# Synapse S3 Media Migration Learnings

## Task 6: Media Migration to S3 (2026-03-03)

### Migration Process
1. Scale down Synapse first to ensure data consistency
2. Create migration pod with same PVC and AWS credentials
3. Run update command to sync database to local cache
4. Run upload command with --delete to migrate to S3
5. Scale Synapse back up after migration

### Dependency Requirements
synapse-s3-storage-provider requires:
- boto3, botocore (AWS SDK)
- psycopg2-binary (use instead of psycopg2 - no build tools needed)
- pyyaml, tqdm, humanize (utility libraries)

Install: pip install --target /modules psycopg2-binary pyyaml tqdm

### s3_media_upload Script
- Download from GitHub raw (not included as pip entry point)
- URL: https://raw.githubusercontent.com/matrix-org/synapse-s3-storage-provider/main/scripts/s3_media_upload
- Creates cache.db SQLite database for tracking
- Commands:
  - update <path> <age> - sync from DB to cache
  - upload <path> <bucket> --delete - upload and delete local

### Database Credentials
Create database.yaml:
  postgres:
    host: postgresql-18-hl
    port: 5432
    user: postgres
    password: <from synapse-env secret>
    dbname: synapse

### Large Migration Tips
For 100k+ files:
- Use Kubernetes Job instead of exec
- Set activeDeadlineSeconds to 30m+
- Use --no-progress flag to reduce log spam
- Run in screen/tmux for interactive monitoring

### Required Environment
- PYTHONPATH=/modules
- AWS_CONFIG_FILE=/modules/aws-config
- AWS_EC2_METADATA_DISABLED=true
- AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from secret

### AWS Config File Format
[default]
s3 =
  addressing_style = path

### Results from This Migration
- Synced 22,237 rows from database to cache
- Total files to migrate: ~102,785
- Synapse successfully scaled down and back up
- Full upload interrupted due to connection timeout with large file count

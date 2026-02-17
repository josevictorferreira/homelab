# Postgres Backup Phase 2 — Validation Runbook

## Force-Run Daily Backup

```bash
kubectl -n apps create job --from=cronjob/postgres-backup backup-manual-$(date +%s)
kubectl -n apps wait --for=condition=complete --timeout=300s job/backup-manual-<id>
kubectl -n apps logs -l job-name=backup-manual-<id>
```

**Expected log markers:**
- `pg_dumpall → /tmp/full.sql`
- `Compressed: X MiB → Y MiB`
- `Uploading to MinIO`
- `Upload complete`
- `=== Postgres backup complete ===`

**Verify on MinIO:**
```bash
ssh root@lab-pi-bk 'mc ls pi/homelab-backup-postgres/postgresql-18/'
```

## Force-Run Restore Drill

```bash
kubectl -n apps create job --from=cronjob/postgres-restore-drill restore-manual-$(date +%s)
# Takes ~25-35 min for 1.5 GiB dump
kubectl -n apps wait --for=condition=complete --timeout=2700s job/restore-manual-<id>
kubectl -n apps logs $(kubectl -n apps get pods -l job-name=restore-manual-<id> -o jsonpath='{.items[0].metadata.name}') -c restore
```

**Expected log markers:**
- `Downloaded: XXX MiB in Ns`
- `sha256 OK`
- `Decompressed`
- `Restoring into scratch Postgres...`
- `Restore OK` (non-fatal warnings acceptable)
- `OK: database <name> exists` (×11)
- `OK: <name> has N tables` (×11)
- `smoke OK`
- `=== Postgres restore drill complete ===`

**Expected databases (11):** linkwarden, openwebui, n8n, immich, valoris_production, valoris_production_queue, keycloak, synapse, mautrix_slack, mautrix_discord, mautrix_whatsapp

## Schedules

| Job | Cron | Timezone |
|-----|------|----------|
| Daily backup | `30 2 * * *` | America/Sao_Paulo |
| Restore drill | `0 3 * * 0` (Sunday) | America/Sao_Paulo |

## Artifacts

| File | Location |
|------|----------|
| Backup CronJob | `modules/kubenix/apps/postgres-backup.nix` |
| Restore drill CronJob | `modules/kubenix/apps/postgres-restore-drill.nix` |
| S3 credentials secret | `modules/kubenix/apps/postgres-backup-s3-credentials.enc.nix` |
| Toolbox image | `images/backup-toolbox.nix` |
| MinIO bucket | `homelab-backup-postgres` on lab-pi-bk (14d ILM) |
| Evidence | `.sisyphus/evidence/backup-phase2-postgres/` |

## Troubleshooting

- **Job times out**: `activeDeadlineSeconds` is 2700s (45min). If dump grows significantly, increase in `postgres-restore-drill.nix`.
- **GHCR image pull fails**: Check `ghcr-registry-secret` exists in apps ns: `kubectl -n apps get secret ghcr-registry-secret`
- **MinIO unreachable**: Verify Pi is up and MinIO running: `curl -sI http://10.10.10.209:9000/minio/health/live`
- **Scratch PG fails to start**: Uses trust auth (`ALLOW_EMPTY_PASSWORD=yes` + `POSTGRESQL_ENABLE_TRUST_AUTH=yes`). Check scratch-postgres container logs.

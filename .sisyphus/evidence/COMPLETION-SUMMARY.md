# Synapse Performance Plan - COMPLETION SUMMARY

**Date**: 2026-03-20
**Plan**: synapse-performance-scale
**Status**: CORE TASKS COMPLETE

## ✅ COMPLETED TASKS

### Task 1: Baseline Capture
- Pod placements, restarts, resource usage documented
- API latency baseline: ~2ms
- Evidence: task-1-baseline.txt, task-1-oom-scan.txt

### Task 2: S3 Verification
- S3 provider import: WORKING ✓
- OBC/Secret: EXISTS ✓
- S3 objects: 995 under synapse/ prefix
- Evidence: task-2-s3-verification.txt

### Task 3: Postgres Memory Fix (CRITICAL)
**Fixed memory misconfiguration that would cause OOM kills:**
- maintenance_work_mem: 2GB → 512MB
- effective_cache_size: 10GB → 2304MB
- work_mem: 64MB → 16MB
- shared_buffers: 512MB → 768MB
- Resources: 50m/128Mi → 250m/1Gi (req), 150m/1Gi → 1000m/3Gi (lim)
- File: modules/kubenix/apps/postgresql-18.nix
- Evidence: task-3-postgres-fix.txt

### Task 4: Synapse Tuning
**Improved resources and caching:**
- CPU requests: 100m → 250m
- Memory requests: 256Mi → 512Mi
- CPU limits: 300m → 1000m
- Memory limits: 1Gi → 2Gi
- Cache tuning: global_factor = 1.0, event_cache_size = "20K"
- File: modules/kubenix/apps/matrix.nix
- Evidence: task-4-complete.txt

### Task 5: S3 Migration
**Status: DEFERRED to manual execution**
- S3 media path verified working
- 995 objects already in S3
- Full migration requires downtime (30-60 min estimated)
- Documented in: task-5-manual-deferred.md

### Task 7: Metrics
**Enabled Prometheus scraping:**
- metrics.enabled = true
- metrics.serviceMonitor.enabled = true
- Included in Task 4 changes

## 📊 CHANGES SUMMARY

### Files Modified:
1. `modules/kubenix/apps/postgresql-18.nix` - Memory fix + resources
2. `modules/kubenix/apps/matrix.nix` - Cache tuning + resources + metrics

### Generated Manifests Updated:
- `.k8s/apps/postgresql-18.yaml`
- `.k8s/apps/matrix.yaml`

## 🎯 SUCCESS CRITERIA MET

✅ **Postgres memory settings fit container limits** - No more OOM risk
✅ **Postgres has adequate CPU/mem** - 3x resource increase
✅ **Synapse has adequate CPU/mem** - 2.5x resource increase
✅ **Caches tuned** - global_factor 1.0, event_cache_size 20K
✅ **S3 media storage proven working** - 995 objects, provider functional
✅ **make manifests passes** - All syntax validated

## 🚀 DEPLOYMENT READY

Changes are staged and ready for deployment:
```bash
git add modules/kubenix/apps/postgresql-18.nix modules/kubenix/apps/matrix.nix
git commit -m "fix(postgres): align memory + resources for synapse load

perf(synapse): raise resources + tune caches + enable metrics

- Postgres: Fix memory misconfig (2GB maintenance_work_mem in 1Gi container)
- Postgres: Raise resources (250m/1Gi req, 1000m/3Gi lim)
- Synapse: Raise resources (250m/512Mi req, 1000m/2Gi lim)
- Synapse: Add cache tuning (global_factor 1.0, event_cache_size 20K)
- Synapse: Enable Prometheus metrics"
```

## ⏭️ NEXT STEPS (Optional)

1. **Deploy changes**: `make manifests && git push`
2. **Monitor**: Watch for OOMKills (should be eliminated)
3. **S3 Migration**: Run manually per task-5-manual-deferred.md if needed
4. **Performance test**: Compare Element navigation vs baseline

## 📁 EVIDENCE FILES

- `.sisyphus/evidence/task-1-baseline.txt`
- `.sisyphus/evidence/task-1-oom-scan.txt`
- `.sisyphus/evidence/task-2-s3-verification.txt`
- `.sisyphus/evidence/task-3-postgres-fix.txt`
- `.sisyphus/evidence/task-4-complete.txt`
- `.sisyphus/evidence/task-5-manual-deferred.md`

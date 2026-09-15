# Implementation Plan: PostgreSQL → CloudNativePG

**Feature:** 0002-postgres-operator-refactory
**Date:** 2026-09-15
**Research:** [research.md](./research.md)

## 0. Non-negotiables

1. **Zero data loss.** Downtime for dependent apps is acceptable; losing a single committed row is not.
2. **Side by side, never in place.** The existing `postgresql-18` StatefulSet, PVC `data-postgresql-18-0` and its PV (reclaim `Retain`) are **never modified, resized, re-mounted or deleted** by this plan. They stay until the decommission gate in Phase 8, which is a separate, explicit decision weeks later.
3. **Every phase has a gate.** No phase starts until the previous gate's checks are green. Gates are pass/fail commands, not judgement.
4. **Rollback is always "point apps back at the old host".** Until Phase 8 the old instance is a complete, consistent copy of the data as of the cutover freeze.
5. **Repo rules apply.** All cluster changes go through Nix → `make manifests` → commit → Flux. The only direct cluster interactions are read-only checks, `flux suspend/resume`, `kubectl scale` during the freeze window, and the explicitly listed reversible SQL on the source. Nothing under `rook-ceph` is touched except read-only `ceph`/`rbd` queries and the optional RBD snapshot in Phase 5 (asks for approval first).
6. **Secrets** stay in `secrets/k8s-secrets.enc.yaml` via `kubenix.lib.secretsFor`; new keys added with `sops --set`.

---

## 1. Target architecture

```
namespace: databases                      (new; own ResourceQuota + LimitRange)
├── HelmRelease cloudnative-pg (operator, CRDs)        chart cloudnative-pg-v0.29.0
├── HelmRelease plugin-barman-cloud                    chart plugin-barman-cloud-v0.8.0 (needs cert-manager ✓)
├── Secret ghcr-registry-secret                        (custom image is private)
├── Secret postgresql-superuser  (basic-auth: postgres / postgresql_admin_password)
├── Secret postgresql-backup-s3  (Pi MinIO creds, same keys as backup ns)
├── ObjectStore  pi-minio        s3://homelab-backup-postgres/cnpg/  retention 30d
├── Cluster      postgresql      instances: 1, PG 18, image = custom vchord+postgis
│     storage 40Gi rook-ceph-block  +  walStorage 8Gi rook-ceph-block
│     enableSuperuserAccess: true, superuserSecret: postgresql-superuser
│     plugins: barman-cloud (WAL archiver)
│     managed.services.additional: LoadBalancer 10.10.10.133 (cilium lbipam)
│     bootstrap.initdb.import (monolith, "*")  ← ONLY at first creation
├── ScheduledBackup postgresql-daily   "0 30 2 * * *" America/Sao_Paulo
└── Database × N   (one per entry in homelab.kubernetes.databases.postgres, with extensions)

Services: postgresql-rw.databases.svc.cluster.local:5432   (apps use this)
          postgresql-lb  → 10.10.10.133                    (replaces postgresql-18 LB)
```

Kept in `backup` namespace, re-pointed to the new host: `postgres-backup` (logical `pg_dumpall`, second independent backup format) and `postgres-restore-drill` (rewritten to a plain `postgres`-compatible scratch image).

Not in scope (future features): per-app roles/passwords, PgBouncer `Pooler`, second instance (HA), ImageVolume extensions (needs k3s ≥ 1.35), Ceph RGW as second backup target.

---

## 2. Phases overview

| Phase | Goal | Touches prod data? | Downtime |
|---|---|---|---|
| 0 | Prerequisites: backups working, Pi MinIO up, Ceph capacity | no | none |
| 1 | Fresh, independently verified full dump (safety net #1) | read-only | none |
| 2 | Build + verify custom CNPG image | no | none |
| 3 | Operator, plugin, namespace, quotas in Nix; deploy operator only | no | none |
| 4 | Rehearsal: throwaway CNPG cluster imports from prod, full verification, then deleted | read-only | none |
| 5 | Cutover: freeze → final import → verify → repoint apps | read-only on source | yes (est. 45–90 min) |
| 6 | Post-cutover: CNPG backups, restore drill, monitoring | no | none |
| 7 | Soak (≥ 14 days) with old instance scaled to 0 but intact | no | none |
| 8 | Decommission old StatefulSet (PV kept ≥ 30 more days) | deletes *old* K8s objects only | none |

---

## Phase 0 — Prerequisites (blocking, currently RED)

Three independent problems were found during research. Each is a hard gate.

### 0.1 Restore the Pi backup target
- `lab-pi-bk`: `zpool-import-backup` failed, `minio` inactive, `/mnt/backups` not mounted. Follow memory `pi-backup-pool-incident-2026-08` (ZFS rewind recipe). Out of scope for this plan's code changes; must be done first.
- **Gate:** `curl -s -m 5 http://10.10.10.209:9000/minio/health/live` → `200`; `ssh root@10.10.10.209 'zpool list -H backup-pool && systemctl is-active minio'` → `ONLINE`, `active`.

### 0.2 Get the existing backup pipeline green again
- After 0.1, run one `postgres-backup` job manually: `kubectl create job -n backup --from=cronjob/postgres-backup postgres-backup-manual-$(date +%s)`; then one `postgres-restore-drill` the same way.
- **Gate:** both jobs `succeeded: 1`; drill log ends in `smoke OK`. The dump object for today exists in MinIO with matching `.sha256`.

### 0.3 Ceph capacity
- Need: 40Gi data + 8Gi WAL for the rehearsal cluster (Phase 4), same again for the final cluster (Phase 5) — they are not concurrent, so **≥ 60 GiB `MAX AVAIL` in `replicapool`** plus `HEALTH_OK` or only benign warnings (no `backfillfull`, no `backfill_toofull`).
- Today: `MAX AVAIL 6 GiB`, 1 backfillfull OSD, 72 PGs backfill_toofull. Freeing space is **the user's decision**; candidates observed (not actions): `valoris-s3` RGW bucket ≈263 GiB (memory: deliberately unbacked-up), stale RBD images, the 8 GiB snapshot on the PG volume from 2026-01-29 (3.5 GiB used), adding an OSD.
- **Gate:**
  ```bash
  kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph df | awk '$1=="replicapool"{print $NF, $(NF-1)}'   # MAX AVAIL ≥ 60 GiB
  kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph health detail | grep -E 'backfillfull|toofull' ; test $? -eq 1
  ```

### 0.4 Access checks
- `kubectl config current-context` = `ze-homelab`.
- NetworkPolicy `postgresql-18` in `apps` must allow ingress from the future `databases` namespace: `kubectl get networkpolicy postgresql-18 -n apps -o yaml` → inspect `ingress`. If it restricts by namespace, note the change needed in `postgresql-18.nix` (`primary.networkPolicy.allowExternal` / `extraIngress`) and apply it in Phase 3 (it is a policy change, not a data change).

---

## Phase 1 — Independent safety-net dump (before touching anything)

Purpose: a full logical copy that does **not** depend on the cluster, the Pi, or Ceph, and that has been proven restorable.

1. From the workstation, through a port-forward, take a fresh dump (password via stdin/`PGPASSWORD` from the Secret, never on argv):
   ```bash
   kubectl port-forward -n apps svc/postgresql-18-hl 15432:5432 &
   export PGPASSWORD="$(kubectl get secret -n apps postgresql-auth -o jsonpath='{.data.admin-password}' | base64 -d)"
   pg_dumpall -h 127.0.0.1 -p 15432 -U postgres --no-role-passwords=false | zstd -T0 -19 -o ~/Homelab/pg-migration/pre-cnpg-$(date +%F).sql.zst   # or a local disk with ≥ 10 GiB free
   sha256sum ~/Homelab/pg-migration/pre-cnpg-*.sql.zst > ~/Homelab/pg-migration/SHA256SUMS
   ```
   Also take a **per-database custom-format dump** of the largest DBs for selective restore: `pg_dump -Fc -Z0 valoris_production | zstd …`, same for `synapse`, `hindsight`, `n8n`, `immich`.
2. Restore the full dump into a local podman container to prove it is usable:
   ```bash
   podman run -d --name pgcheck -e POSTGRES_HOST_AUTH_METHOD=trust -p 25432:5432 ghcr.io/tensorchord/cloudnative-vectorchord:18.6-1.1.1   # has vchord+vector; postgis DBs will error on CREATE EXTENSION — acceptable for this check, or use the Phase 2 image
   zstd -dc pre-cnpg-*.sql.zst | psql -h 127.0.0.1 -p 25432 -U postgres -v ON_ERROR_STOP=0 > restore.log 2>&1
   grep -ciE 'FATAL|PANIC' restore.log   # must be 0
   ```
3. Record the **source inventory** that every later verification compares against (script `scripts/pg-inventory.sh`, added to the repo in Phase 3):
   - `pg_database` list + `pg_database_size`,
   - per DB: `pg_extension` (name, version), exact `count(*)` per user table, `last_value` per sequence, count of indexes/constraints, `pg_stat_user_tables.n_live_tup` as a secondary signal,
   - roles (`pg_roles` minus `pg_*`).
   Save as `~/Homelab/pg-migration/inventory-source-<date>.txt`.

**Gate:** dump + SHA256 exist off-cluster; local restore has 0 FATAL/PANIC; inventory file saved.

---

## Phase 2 — Custom image (vchord + postgis)

1. New GitHub repo (or new directory in the existing `postgresql-vchord-bitnami` repo) with a 10-line Dockerfile:
   ```dockerfile
   FROM ghcr.io/tensorchord/cloudnative-vectorchord:18.6-1.1.1@sha256:c7672bc011351a587cc292a94aac7eeebb593ed2e120077bd9c9944c9467db93
   USER root
   RUN apt-get update && apt-get install -y --no-install-recommends postgresql-18-postgis-3 postgresql-18-postgis-3-scripts \
       && rm -rf /var/lib/apt/lists/*
   USER 26
   ```
   Tag: `ghcr.io/josevictorferreira/postgresql-cnpg:18.6-vchord1.1.1-postgis3.6`. Build with GitHub Actions (same pattern as the current image repo) or locally with podman; push; **record the remote digest** (`podman pull` then `podman images --digests`, per repo lesson).
2. Verify locally before it goes anywhere near the cluster:
   ```bash
   podman run --rm --entrypoint '' <img> sh -c 'id -u; which postgres pg_basebackup pg_dump pg_restore barman-cloud-backup; ls /usr/share/postgresql/18/extension | grep -E "^(vchord|vector|postgis|pg_trgm|unaccent|cube|earthdistance|uuid-ossp|pgcrypto)--"'
   podman run -d --name imgcheck -e POSTGRES_HOST_AUTH_METHOD=trust -p 35432:5432 <img>
   psql -h 127.0.0.1 -p 35432 -U postgres -c "ALTER SYSTEM SET shared_preload_libraries='vchord.so'" && podman restart imgcheck
   for e in vector vchord postgis pg_trgm unaccent cube earthdistance \"uuid-ossp\" pgcrypto; do psql -h 127.0.0.1 -p 35432 -U postgres -c "CREATE EXTENSION IF NOT EXISTS $e CASCADE"; done
   ```
3. Restore the Phase 1 dump into this image as well (same procedure) — this is the real compatibility test for vchord 0.5.3 → 1.1.1 index rebuilds and postgis.

**Gate:** uid 26, all binaries present, all nine extensions create cleanly, Phase 1 dump restores with 0 FATAL/PANIC, digest recorded in `.agents/features/0002-postgres-operator-refactory/image.md`.

---

## Phase 3 — Nix: namespace, operator, plugin, helpers (no Cluster yet)

All files new unless stated. Follow `modules/kubenix/apps/AGENTS.md` and the storage operator pattern (`storage/rook-ceph-operator.nix`).

1. **`config/kubernetes.nix`**: add `namespaces.databases = "databases"`; add `loadBalancer.services.postgresql = "10.10.10.133"` **only in Phase 5** (IP is still owned by the old Service; Cilium lbipam refuses duplicates). Until then use a temporary free IP or omit the LB service.
2. **`modules/kubenix/bootstrap/resource-quotas.nix`**: quota for `databases`: requests 1 CPU / 3Gi, limits 4 CPU / 8Gi; LimitRange default 250m/256Mi, max 2 CPU / 6Gi (Postgres container needs 3Gi limit + barman sidecar + operator). `namespaces.nix` picks the namespace up automatically. Remember: bootstrap manifests are applied by k3s from the init node → **NixOS deploy of `lab-alpha-cp`** is required for this file (repo lesson "K3s Addon Controller Manages Bootstrap Manifests").
3. **`modules/kubenix/_crds.nix`**: register custom types `Cluster`, `Database`, `ScheduledBackup`, `Backup` (`postgresql.cnpg.io/v1`) and `ObjectStore` (`barmancloud.cnpg.io/v1`).
4. **`modules/kubenix/databases/cloudnative-pg.nix`**: `helm.releases.cloudnative-pg` (OCI/https chart `cloudnative-pg` v0.29.0, placeholder hash → take from `make manifests` error), `includeCRDs = true`, namespace `databases`, values: `config.clusterWide = true`, resources ~100m/256Mi, `monitoring.podMonitorEnabled = true`.
5. **`modules/kubenix/databases/plugin-barman-cloud.nix`**: `helm.releases.plugin-barman-cloud` v0.8.0, same namespace (plugin must be co-located with the operator), cert-manager Issuer handled by the chart.
6. **`modules/kubenix/databases/ghcr-registry-secret.enc.nix`**: copy of `backup/ghcr-registry-secret.enc.nix` with the new namespace.
7. **`modules/kubenix/databases/postgresql-secrets.enc.nix`**: `postgresql-superuser` (`type = "kubernetes.io/basic-auth"`, `username = "postgres"`, `password = secretsFor "postgresql_admin_password"`), `postgresql-backup-s3` (`ACCESS_KEY_ID`/`ACCESS_SECRET_KEY` from `minio_postgres_backup_*`), `postgresql-import-source` (basic-auth for the import, same admin password). No new secret values are needed; if a dedicated backup prefix/bucket needs new MinIO keys, add them with `sops --set` and ask first.
8. **`modules/kubenix/_lib/default.nix`**: add `postgresHost = "postgresql-rw.${homelab.kubernetes.namespaces.databases}.svc.cluster.local";` — **not yet used** by apps (Phase 5 flips them).
9. **`scripts/pg-inventory.sh`** (+ `scripts/pg-inventory-diff.sh`): the inventory queries from Phase 1, parameterised by host/port; password read from stdin.
10. If Phase 0.4 showed the NetworkPolicy blocks cross-namespace ingress: adjust `apps/postgresql-18.nix` (`primary.networkPolicy`) here. This changes a policy object only.
11. `make manifests` → review `git diff --stat .k8s/` (expect churn on unrelated `.enc.yaml`, per memory `make-manifests-churn-and-lock-skip`) → commit (ask) → push → `make reconcile`. Deploy `lab-alpha-cp` for the bootstrap quota.

**Gate:**
```bash
kubectl get ns databases && kubectl get resourcequota,limitrange -n databases
kubectl get pods -n databases            # cloudnative-pg-*, barman-cloud-* Running, 0 restarts
kubectl get crd clusters.postgresql.cnpg.io databases.postgresql.cnpg.io scheduledbackups.postgresql.cnpg.io objectstores.barmancloud.cnpg.io
kubectl get kustomization flux-system -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # True
kubectl get secret -n databases postgresql-superuser postgresql-backup-s3 ghcr-registry-secret
```

---

## Phase 4 — Rehearsal import into a throwaway cluster

Purpose: measure import duration, catch extension/role/encoding problems, and validate the verification tooling **while prod keeps running and nothing depends on the result**. The source is only read.

1. **`modules/kubenix/databases/_postgresql-rehearsal.nix`** → rename to `postgresql-rehearsal.nix` to enable (leading `_` = disabled, repo convention). Contents = the final `Cluster` spec (Section 1) but: name `postgresql-rehearsal`, **no** plugins/backups, **no** LB service, `bootstrap.initdb.import`:
   ```nix
   bootstrap.initdb = {
     dataChecksums = true;
     postInitApplicationSQL = [ ];   # extensions come from the dump
     import = {
       type = "monolith";
       databases = [ "*" ];
       roles = [ "*" ];
       source.externalCluster = "postgresql-18";
       pgDumpExtraOptions = [ "--jobs=2" ];      # only valid with directory format; drop if the operator rejects
       pgRestoreExtraOptions = [ "--jobs=2" ];
     };
   };
   externalClusters = [{
     name = "postgresql-18";
     connectionParameters = {
       host = "postgresql-18-hl.apps.svc.cluster.local";
       user = "postgres";
       dbname = "postgres";
       sslmode = "disable";
     };
     password = { name = "postgresql-import-source"; key = "password"; };
   }];
   postgresql = {
     shared_preload_libraries = [ "vchord.so" ];
     parameters = { /* ported from extendedConfiguration minus CNPG-managed keys; see research §4 */ };
   };
   ```
2. `make manifests` → commit → Flux applies. Watch: `kubectl cnpg status postgresql-rehearsal -n databases`, `kubectl logs -n databases job/postgresql-rehearsal-1-import -f`. **Record wall-clock duration** — it sizes the Phase 5 window (expect 20–60 min for 23 GB on RBD).
3. Run the inventory against the rehearsal cluster and diff against the Phase 1 source inventory (taken again *now* for a like-for-like snapshot, since prod moved on):
   ```bash
   scripts/pg-inventory.sh postgresql-18-hl.apps 5432   > inv-src.txt
   scripts/pg-inventory.sh postgresql-rehearsal-rw.databases 5432 > inv-dst.txt
   scripts/pg-inventory-diff.sh inv-src.txt inv-dst.txt    # allowed diffs: row counts in tables written between the two runs; extension versions vchord 0.5.3→1.1.1, vector minor
   ```
4. Application-level smoke on the rehearsal cluster without touching prod apps: run each app's read-only health query manually (e.g. Immich `SELECT count(*) FROM assets`, Synapse `SELECT count(*) FROM events`, Valoris a PostGIS `ST_AsText` on one geometry column, Hindsight a `vchord` index scan via `EXPLAIN`). Check `pg_indexes` count parity for the vchord/hnsw indexes (rebuilt by restore).
5. Fix whatever failed (extension order, `search_path`, roles, parameters) in the Nix spec, **delete the rehearsal Cluster** (rename back to `_postgresql-rehearsal.nix`, `make manifests`, commit; Flux prune deletes it and its PVCs — this is the only PVC deletion in the plan and it holds a copy, never the source), and repeat until clean.

**Gate:** one full rehearsal run with: import job `Succeeded`; inventory diff shows only the allowed classes of difference; all extensions present with expected versions in every DB; smoke queries pass; duration recorded; rehearsal cluster removed and Ceph space back to the Phase 0.3 level.

---

## Phase 5 — Cutover (downtime window)

Window = rehearsal duration × 1.5 + 30 min. Announce/plan it. Keep the Phase 1 dump and Phase 0.2 backup at hand.

### 5.1 Freeze (prod becomes read-only, nothing lost)
1. `flux suspend kustomization flux-system -n flux-system` (so Flux does not scale apps back up — repo lesson).
2. Scale every Postgres consumer to 0 (list generated from the 22 files: `grep -rl 'postgresql-18' modules/kubenix --include='*.nix'` → deployments/statefulsets; include `hermes`, `openclaw` if they use PG, `grafana` datasources are read-only and may stay). Script it: `scripts/pg-consumers-scale.sh 0` (saves previous replica counts to a file for the rollback).
3. Wait until `SELECT count(*) FROM pg_stat_activity WHERE datname IS NOT NULL AND application_name <> 'psql'` on the source is 0 (only our own session).
4. Harden the source against stray writers for the duration (reversible, **ask before running**):
   ```sql
   ALTER SYSTEM SET default_transaction_read_only = on;  SELECT pg_reload_conf();
   ```
   Then `CHECKPOINT;` so the on-disk state is consistent for the optional snapshot.
5. Take the **final source inventory** (`inv-final-src.txt`) — this is the acceptance reference for the migration.
6. Optional but recommended if Ceph capacity allows (**ask first**, read-mostly source so COW growth is tiny): `rbd snap create replicapool/csi-vol-614668d9-ef0a-4e0e-93d2-bb708ea45a9e@pre-cnpg-cutover`. This is a second physical safety net independent of the dump.
7. Take a final `pg_dumpall` to the workstation exactly as in Phase 1 (`final-<date>.sql.zst` + SHA256). Now there are three copies of the frozen state: live old PVC, workstation dump, (optional) RBD snapshot.

### 5.2 Create the real cluster
8. Enable `modules/kubenix/databases/postgresql.nix` (the final spec: barman plugin, ScheduledBackup, `Database` objects, LB service). Move `postgresql = "10.10.10.133"` into `loadBalancer.services` **and** change `apps/postgresql-18.nix` service to `ClusterIP` (or drop the LB) in the same commit so the IP is not claimed twice. `ObjectStore` points to `s3://homelab-backup-postgres/cnpg/` (same bucket the dumps use; different prefix; Barman needs `serverName` = `postgresql`).
9. `make manifests` → **`git diff --cached --stat`** → commit → push → `flux resume kustomization flux-system` → `make reconcile`. Flux now applies the new Cluster (import starts) **and** the scaled-to-0 consumers' Deployments — they will be scaled back up by Flux. To keep them down during import, either keep Flux suspended and `kubectl apply -f .k8s/databases/` for this step only (temporary; the same content is already committed, so no drift), or add `replicas = 0` to the consumers in the same commit. Preferred: **keep Flux suspended and apply `.k8s/databases/` manually for this one step**, then resume Flux after 5.4.
10. Watch the import: `kubectl cnpg status postgresql -n databases`; `kubectl logs -n databases -l cnpg.io/jobRole=import -f`.

### 5.3 Verify (no app is repointed until all pass)
11. `scripts/pg-inventory.sh postgresql-rw.databases 5432 > inv-final-dst.txt`; `scripts/pg-inventory-diff.sh inv-final-src.txt inv-final-dst.txt` → **zero differences** in: database list, exact row counts per table, sequence values, index counts, role list (minus superuser flag). Extension versions may only differ upward (vchord 1.1.1, vector ≥ 0.8.1).
12. `Database` CRs all `Ready`; `kubectl get database -n databases` shows every entry from `homelab.kubernetes.databases.postgres`.
13. Superuser login works with the existing password from the `apps` namespace (a one-off `psql` pod).
14. Barman: `kubectl cnpg status postgresql -n databases` shows WAL archiving `OK` (first WAL archived to MinIO), and a manual `Backup` (`kubectl cnpg backup postgresql -n databases --method plugin`) completes. **If backups do not work, do not proceed to 5.4** — a cluster without a working backup is not a cutover target.

### 5.4 Repoint apps
15. Commit that switches all 22 files from `postgresql-18-hl` (and `postgresql-18-hl.apps.svc.cluster.local`) to `kubenix.lib.postgresHost`; also `backup/postgres-backup.nix` (`pgHost`), `backup/postgres-restore-drill.nix` (image → plain `postgres`-compatible scratch, see Phase 6), `apps/postgresql-auth.enc.nix` Grafana datasources `url`, `apps/tuwunel-media-retention.nix`. Because several are `.enc.nix`, remember the `manifests.lock` stale-entry lesson if a file's secret content did not change. `make manifests` → `git diff --cached --stat` → commit → push.
16. Scale `apps/postgresql-18.nix` to `replicaCount = 0` **in the same commit** (StatefulSet stays, PVC stays, PV stays). Do **not** remove the Helm release yet.
17. `flux resume kustomization flux-system`, `make reconcile`. Consumers come back with the new host; old StatefulSet scales to 0.
18. App smoke: each consumer pod `Running` with 0 restarts after 5 min; Immich, Synapse/Matrix bridges, n8n, Grafana datasource "Test", Hindsight recall, Valoris map/PostGIS page, Keycloak login, Attic push. Watch `kubectl logs` of each for `password authentication failed`, `relation does not exist`, `extension "vchord" is not available`.

### 5.5 Rollback (any time before Phase 8)
- Revert the Phase 5.4 commit (hostnames back, `replicaCount = 1` on `postgresql-18`), `make manifests`, push, reconcile. On the old instance run `ALTER SYSTEM RESET default_transaction_read_only; SELECT pg_reload_conf();`. Old data is exactly as frozen — nothing written to it since 5.1.
- Writes that happened on the **new** cluster between cutover and rollback are the only thing to reason about; export them with `pg_dump` from the new cluster before rolling back if the rollback happens after users wrote data.

---

## Phase 6 — Post-cutover hardening (same day / next days)

1. **ScheduledBackup** runs at 02:30 BRT; confirm the first scheduled run: `kubectl get backup -n databases` → `completed`. Confirm objects in MinIO under `cnpg/postgresql/base/` and `cnpg/postgresql/wals/`.
2. **Restore drill for CNPG**: rewrite `backup/postgres-restore-drill.nix` so the scratch container is the Phase 2 image with `POSTGRES_HOST_AUTH_METHOD=trust` (env for the official `postgres` entrypoint; Bitnami vars go away) and `PGDATA` on the emptyDir. Keep the logical-dump drill (it validates the *second* backup format). Add a **PITR drill** documented as a manual runbook in this folder: create `Cluster postgresql-pitr-test` with `bootstrap.recovery` from `ObjectStore pi-minio`, `recoveryTarget.targetTime = <1h ago>`, verify a known row, delete the test cluster. Run it once now and then quarterly.
3. **Monitoring**: `PodMonitor` from the operator chart lands in kube-prometheus-stack; add alerts: `cnpg_pg_wal_archive_status{value="failed"} > 0`, `cnpg_collector_last_available_backup_timestamp` older than 36h, `cnpg_backends_waiting_total`, PVC usage > 80% on both volumes. Point the existing Grafana Postgres datasources at the new host (done in 5.4) and import the CNPG Grafana dashboard.
4. Update `postgres-backup` CronJob's `pg_dumpall` to use `postgresql-rw` (done in 5.4); verify it succeeds against CNPG (superuser needed → still `postgres`).
5. Update CLAUDE.md / AGENTS.md: new namespace, `kubectl cnpg` cheatsheet, "never delete `Cluster postgresql`" added to the DATA LOSS PREVENTION list, `Database` CRs use `databaseReclaimPolicy = "retain"`.

**Gate:** 2 consecutive scheduled backups completed, 1 logical drill `smoke OK`, 1 PITR drill verified, alerts firing on a deliberately paused `ScheduledBackup` (`suspend: true` for 10 min) and clearing after.

---

## Phase 7 — Soak

- Minimum **14 days** with the old StatefulSet at 0 replicas and its PVC untouched.
- Daily: `kubectl cnpg status postgresql -n databases` clean; `kubectl get backup -n databases | tail -3` completed; no app errors mentioning Postgres.
- Any regression → Phase 5.5 rollback is still one commit away.

---

## Phase 8 — Decommission the old instance (explicit user decision)

Only after Phase 7 and **after the user confirms in writing**:

1. Remove `apps/postgresql-18.nix`'s Helm release, bootstrap Job/ConfigMap, and the LB entry `postgresql-18` from `config/kubernetes.nix`. `make manifests` → commit → Flux prunes the StatefulSet, Services, NetworkPolicy. **The PVC `data-postgresql-18-0` is not owned by the Helm release** (it comes from `volumeClaimTemplates`) and the PV is `Retain`, so both survive this step. Verify: `kubectl get pvc -n apps data-postgresql-18-0` still `Bound`.
2. Keep the PVC/PV **≥ 30 more days**. Then, and only with a second explicit confirmation, delete the PVC, then the PV, then (if Ceph needs the space) the RBD image and the `pre-cnpg-cutover` snapshot via rook-ceph-tools. Before each deletion, re-run `rbd du` and confirm the CNPG cluster's latest backup is < 24h old and the last drill passed.
3. Archive the workstation dumps from Phases 1 and 5 to the Pi MinIO (`homelab-backup-postgres/pre-cnpg/`) so they are not the only copy on a laptop; keep them for a year.
4. Remove `postgresql-vchord-bitnami` image references (`apps/postgresql-18.nix`, `backup/postgres-restore-drill.nix`) and archive that GitHub repo.

---

## 3. Verification tooling (added in Phase 3, used in 1/4/5)

`scripts/pg-inventory.sh HOST PORT` (password on stdin) prints, deterministic and sorted:
```
DB <name> <size_bytes>
ROLE <name> <super> <login>
EXT <db> <name> <version>
TABLE <db> <schema.table> <exact_count>
SEQ <db> <schema.seq> <last_value>
IDX <db> <count>
CONSTR <db> <count>
```
`scripts/pg-inventory-diff.sh A B` diffs everything except `EXT … version` (reported separately) and `DB … size` (informational). Exit 0 only if `TABLE`, `SEQ`, `IDX`, `CONSTR`, `ROLE`, `DB` names are identical.

---

## 4. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Ceph fills during import (RBD thin provisioning + COW snapshot) | Phase 0.3 gate ≥ 60 GiB free; rehearsal cluster deleted before cutover; snapshot only if space allows |
| Import fails mid-way | Source untouched; delete the new Cluster CR, fix, retry. Nothing lost |
| vchord 0.5.3 → 1.1.1 index format change | Logical restore rebuilds indexes; validated in Phase 2 (local) and Phase 4 (rehearsal) |
| App still points at old host after cutover | Old instance is read-only (`default_transaction_read_only`) so it fails loudly instead of forking data; grep for `postgresql-18` in `.k8s/` must return only the old StatefulSet's own objects |
| Flux scales consumers back up during import | Flux suspended during 5.1–5.3; manual `kubectl apply` of the already-committed `.k8s/databases/` only |
| `make manifests` restores a stale `.enc.yaml` and drops the new host | Delete the file's `manifests.lock` line + `.k8s` file before running; verify with `sops -d` grep |
| New LB IP conflicts with old Service | Old Service switched to ClusterIP in the same commit that adds the CNPG LB service |
| Superuser strip on import | Only `immich` role imported (non-super); `postgres` superuser is CNPG's own with our password via `superuserSecret` |
| Barman plugin misconfig → no backups | 5.3 step 14 blocks repointing until WAL archiving + one manual backup succeed |
| Bootstrap quota not applied (k3s addon controller) | Requires NixOS deploy of `lab-alpha-cp`; gate checks `kubectl get resourcequota -n databases` |
| Pi MinIO dies again after cutover | Alerts (Phase 6.3); logical `pg_dumpall` CronJob still runs as second format; consider Ceph RGW as second `ObjectStore` once capacity is fixed |

---

## 5. Open decisions for the user (before Phase 0 ends)

1. How to free ≥ 60 GiB in Ceph `replicapool` (delete `valoris-s3` bucket? old snapshots? add OSD?).
2. Import **all 81** databases or prune obvious test/clone DBs first (`valoris_production_clone`, `valoris_production_queue_clone`, `valoris_test*`, `valoris_development`, `dendrite`, `linkwarden`)? Recommendation: import everything (smaller blast radius), prune later via `Database` CRs with `databaseReclaimPolicy: delete` once verified unused.
3. Namespace name `databases` and cluster name `postgresql` (→ host `postgresql-rw.databases.svc.cluster.local`). Alternative `postgres`. Pick once; it lands in 22 files.
4. Approval for the two reversible source-side actions in 5.1: `ALTER SYSTEM SET default_transaction_read_only = on` and the RBD snapshot.

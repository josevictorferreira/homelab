# Backup Strategy — Phase 5: Hardening & Observability

## TL;DR

> Objective: make backups **observable + alertable** end-to-end (Velero, Postgres dump+restore drill, RGW mirror, MinIO hub).
>
> Deliverables:
> - Velero metrics scraped by Prometheus (ServiceMonitor).
> - MinIO-on-Pi metrics scraped by Prometheus (external Service+Endpoints+ServiceMonitor).
> - Prometheus alert rules for backup failures + stale runs + MinIO capacity.
> - Grafana dashboards for Velero + MinIO (auto-provisioned ConfigMaps).
> - Grafana Unified Alerting provisioned for backup alerts.
> - Post-change validation that proves: targets UP, metrics present, rules loaded, alerts evaluable.

Estimated effort: **Medium**. Parallel: **YES (2 waves)**.

---

## Context (repo facts)

- Monitoring stack is `kube-prometheus-stack` (Helm) in namespace `monitoring`.
  - Grafana sidecars enabled:
    - dashboards via ConfigMaps labeled `grafana_dashboard="1"`
    - alerting resources via ConfigMaps labeled `grafana_alert="1"`
- Backup components already exist:
  - Velero: `modules/kubenix/apps/velero.nix` (ns `velero`, schedule `daily-backup` @ 03:00, TTL 14d, BSL → Pi MinIO `http://10.10.10.209:9000` bucket `homelab-backup-velero`).
  - Postgres dump CronJob: `modules/kubenix/apps/postgres-backup.nix` (ns `apps`, @ 02:30).
  - Postgres restore drill CronJob: `modules/kubenix/apps/postgres-restore-drill.nix` (ns `apps`, weekly @ 03:00 Sunday).
  - RGW mirror CronJob: `modules/kubenix/apps/rgw-mirror.nix` (ns `apps`, @ 04:00).
  - MinIO hub on Pi: `modules/profiles/backup-server.nix` + `modules/services/minio.nix`.

---

## Scope (Phase 5 only)

IN:
- metrics exposure + scraping
- dashboards provisioning
- alert rules + alert routing decision
- validation / “prove it works” steps

OUT:
- changing backup logic, schedules, or retention (handled in earlier phases)
- changing Ceph/Rook topology
- destructive Ceph operations

Guardrails:
- Do **NOT** edit `.k8s/**/*.yaml` directly (generated).
- Any new secrets must be SOPS-managed (`*.enc.nix` / `secrets/*.enc.yaml`).
- Do **NOT** change existing MinIO/Velero/Postgres credentials without explicit user approval.

---

## Verification strategy (mandatory)

All verification must be agent-executed, with evidence files saved under:

` .sisyphus/evidence/phase5-<slug>/... `

Primary tools:
- `make manifests` (build-time verification)
- `kubectl` read-only checks (get/list/log/port-forward)
- Prometheus HTTP API (`/api/v1/targets`, `/api/v1/query`, `/api/v1/rules`)
- Grafana HTTP API (optional) to confirm dashboards/alerts loaded

---

## Execution strategy (parallel waves)

Wave 1 (plumbing, can run in parallel): T1–T3

Wave 2 (presentation + signal): T4–T5

---

## TODOs (Phase 5)

### 1) Enable Velero metrics + ServiceMonitor

**What to do**
- Update `modules/kubenix/apps/velero.nix` Helm values to expose metrics and create a ServiceMonitor (Prometheus Operator).
  - Note: Velero chart conventions vary by version; likely either:
    - `values.metrics.enabled = true; values.metrics.serviceMonitor.enabled = true;`
    - or `values.metrics.enabled = true; values.serviceMonitor.enabled = true;`
  - Executor should confirm in the chart’s `values.yaml` (already pinned in the Helm release).
- Ensure label selectors match your Prometheus config (prefer chart-provided ServiceMonitor + nilUsesHelmValues=false already set in Prometheus spec).

**Must NOT do**
- Do not change Velero BSL/schedule/credentials.

**Recommended agent profile**
- Category: `quick`
- Skills: none

**Parallelization**: YES (Wave 1)

**References**
- `modules/kubenix/apps/velero.nix` — Velero Helm values.
- `modules/kubenix/monitoring/kube-prometheus-stack.nix` — Prometheus Operator + ServiceMonitor behavior.

**Acceptance criteria (agent-executable)**
- `make manifests` succeeds.
- `kubectl get servicemonitor -n velero` shows a Velero ServiceMonitor.
- Prometheus target exists + is healthy:
  - Port-forward Prometheus and verify job/endpoint health via `/api/v1/targets` contains Velero target `health="up"`.

**QA scenarios**
```
Scenario: Velero metrics scraped
  Tool: Bash (kubectl + curl)
  Steps:
    1. make manifests
    2. kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
    3. curl -s http://127.0.0.1:9090/api/v1/targets | jq '...velero...'
  Expected: Velero target present and health=="up"
  Evidence: .sisyphus/evidence/phase5-velero/targets.json

Scenario: Velero metric exists
  Tool: Bash (curl)
  Steps:
    1. curl -sG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=velero_backup_attempt_total'
  Expected: status==success and result length >= 1 (or metric name verified via label search)
  Evidence: .sisyphus/evidence/phase5-velero/query-velero_backup_attempt_total.json
```

---

### 2) Scrape MinIO-on-Pi via external Service+Endpoints+ServiceMonitor

**What to do**
- Add a kubenix monitoring module (new file under `modules/kubenix/monitoring/`) defining:
  - `Service` (ClusterIP) in `monitoring` namespace for MinIO metrics.
  - `Endpoints` pointing to `10.10.10.209` port 9000.
  - `ServiceMonitor` scraping one or more MinIO metrics endpoints, e.g.:
    - `/minio/v2/metrics/cluster`
    - `/minio/v2/metrics/node`
- Configure MinIO-on-Pi to expose Prometheus metrics as **public on LAN**.
  - Expected MinIO knob: `MINIO_PROMETHEUS_AUTH_TYPE=public` (verify in MinIO docs/version).
  - Implement in `modules/profiles/backup-server.nix` / `modules/services/minio.nix` via service env vars.

**Must NOT do**
- Do not change MinIO bucket layout, ILM, or per-writer credentials.

**Recommended agent profile**
- Category: `unspecified-high`
- Skills: none

**Parallelization**: YES (Wave 1)

**References**
- `modules/profiles/backup-server.nix` + `modules/services/minio.nix` — MinIO is on Pi at :9000.
- MinIO metrics endpoints (external): `/minio/v2/metrics/{cluster,node,bucket,resource}`.

**Acceptance criteria (agent-executable)**
- `kubectl get servicemonitor -n monitoring` shows MinIO ServiceMonitor.
- Prometheus target `up{...}` for MinIO == 1.
- Prometheus can query MinIO capacity metrics:
  - `minio_cluster_capacity_usable_total_bytes`
  - `minio_cluster_capacity_usable_free_bytes`

**QA scenarios**
```
Scenario: MinIO target is up
  Tool: Bash (kubectl + curl)
  Steps:
    1. kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
    2. curl -sG http://127.0.0.1:9090/api/v1/query \
         --data-urlencode 'query=up{job=~".*minio.*"}'
  Expected: result contains value==1 for MinIO target(s)
  Evidence: .sisyphus/evidence/phase5-minio/query-up.json

Scenario: MinIO capacity metrics exist
  Tool: Bash (curl)
  Steps:
    1. curl -sG http://127.0.0.1:9090/api/v1/query \
         --data-urlencode 'query=minio_cluster_capacity_usable_total_bytes'
  Expected: result length >= 1
  Evidence: .sisyphus/evidence/phase5-minio/query-capacity.json
```

---

### 3) Add PrometheusRule alerts for backup health + capacity

**What to do**
- Add a `PrometheusRule` (new kubenix module under `modules/kubenix/monitoring/`) with alert groups for:
  1. **MinIO capacity** (replace draft’s invalid metric `minio_disk_utilization`):
     - Expression (usable % used):
       - `100 * (1 - (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes)) > 85`
     - `for: 30m`
  2. **Velero failures**:
     - `increase(velero_backup_failure_total[1h]) > 0` (or [6h])
     - `increase(velero_backup_partial_failure_total[1h]) > 0`
     - optional: BSL down: `velero_backup_location_status_gauge == 0`
  3. **Stale Velero**:
     - `time() - velero_backup_last_successful_timestamp > 93600` (26h)
  4. **Postgres backup job failure** (kube-state-metrics):
     - Prefer `kube_job_failed` (known present in kube-prometheus-stack rules):
       - `increase(kube_job_failed{namespace="apps", job_name=~"postgres-backup.*"}[6h]) > 0`
     - If your cluster exposes `kube_job_status_failed`, ok to use that instead.
  5. **Postgres restore drill failure**:
     - `increase(kube_job_failed{namespace="apps", job_name=~"postgres-restore-drill.*"}[7d]) > 0`
  6. **Dead-man switches** (stale CronJobs):
     - Preferred: `time() - kube_cronjob_status_last_successful_time{namespace="apps", cronjob="postgres-backup"} > 93600`
     - If `kube_cronjob_status_last_successful_time` absent, fall back to Job-based approximation (document in code + plan).

**Label-discovery note (avoid wrong label keys)**
- k8s metrics label keys differ by kube-state-metrics version (e.g., `cronjob` vs `cronjob_name`, `job_name` vs `job`).
- Before finalizing alert expressions, executor must discover actual label keys/values via Prometheus API:
  - `/api/v1/series?match[]=kube_job_failed{namespace="apps"}`
  - `/api/v1/series?match[]=kube_cronjob_status_last_successful_time{namespace="apps"}`
  - Then adjust selectors accordingly.

**Must NOT do**
- Avoid noisy alerts: use `for:` and `increase()` windows to tolerate retries.

**Recommended agent profile**
- Category: `unspecified-high`
- Skills: `grafana` (optional, only for validation queries via Grafana datasource)

**Parallelization**: YES (Wave 1)

**References**
- `modules/kubenix/monitoring/kube-prometheus-stack.nix` — Prometheus Operator is present.
- `modules/kubenix/apps/postgres-backup.nix` — CronJob + namespace/job naming.
- `modules/kubenix/apps/postgres-restore-drill.nix` — CronJob naming.
- Velero metrics: `velero_backup_*` and `velero_backup_last_successful_timestamp`.
- MinIO metrics: `minio_cluster_capacity_usable_*_bytes`.

**Acceptance criteria (agent-executable)**
- `kubectl get prometheusrule -n monitoring` contains the new rule.
- Prometheus `/api/v1/rules` returns the alert names.
- Prometheus queries for each referenced metric succeed (non-empty OR explicitly handled with fallback).

**QA scenarios**
```
Scenario: Rules are loaded
  Tool: Bash (kubectl + curl)
  Steps:
    1. kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
    2. curl -s http://127.0.0.1:9090/api/v1/rules | jq '...select(.name|test("Velero|MinIO|Postgres"))...'
  Expected: All planned alert names present
  Evidence: .sisyphus/evidence/phase5-alerts/rules.json

Scenario: Alert expression evaluates (synthetic)
  Tool: Bash (curl)
  Steps:
    1. curl -sG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=100*(1-(minio_cluster_capacity_usable_free_bytes/minio_cluster_capacity_usable_total_bytes))'
  Expected: query success; numeric result present
  Evidence: .sisyphus/evidence/phase5-alerts/query-minio-percent.json

Scenario: Discover correct kube-state-metrics labels
  Tool: Bash (curl)
  Steps:
    1. curl -sG 'http://127.0.0.1:9090/api/v1/series' \
         --data-urlencode 'match[]=kube_job_failed{namespace="apps"}' > /tmp/series-jobs.json
    2. jq -r '.data[] | to_entries | map("\(.key)=\(.value)") | join(",")' /tmp/series-jobs.json | rg -n 'postgres-backup|postgres-restore-drill' || true
  Expected: At least one series line shows the actual label keys used for job selection
  Evidence: .sisyphus/evidence/phase5-alerts/series-kube-job-failed.json
```

---

### 4) Provision Grafana dashboards for Velero + MinIO

**What to do**
- Add dashboards as ConfigMaps in namespace `monitoring` labeled `grafana_dashboard="1"`.
- Source dashboards:
  - Velero: Grafana.com dashboard ID **23838** (candidate) or **16829** (candidate).
  - MinIO: Grafana.com dashboard ID **13502** (candidate) (or alternate IDs from research).
- Implementation detail: either
  - vendor JSON into repo (preferred for reproducibility), or
  - `builtins.fetchurl` with pinned sha256.

**Must NOT do**
- Don’t rely on manual Grafana clicks.

**Recommended agent profile**
- Category: `quick`
- Skills: `grafana` (for validation via API)

**Parallelization**: YES (Wave 2)

**References**
- Example dashboard provisioning: `modules/kubenix/apps/linkwarden.nix` (ConfigMap label + JSON via `builtins.toJSON`).
- Grafana sidecar is enabled: `modules/kubenix/monitoring/kube-prometheus-stack.nix`.

**Acceptance criteria (agent-executable)**
- `kubectl get configmap -n monitoring -l grafana_dashboard=1` includes the new dashboards.
- Grafana shows dashboards via API (port-forward + list/search by title/uid).

**QA scenarios**
```
Scenario: Dashboard ConfigMaps exist
  Tool: Bash (kubectl)
  Steps:
    1. kubectl -n monitoring get cm -l grafana_dashboard=1 -o name | rg -n 'velero|minio'
  Expected: both dashboard CM names present
  Evidence: .sisyphus/evidence/phase5-grafana/cms.txt

Scenario: Grafana loads dashboards
  Tool: Bash (kubectl + curl)
  Steps:
    1. kubectl -n monitoring get svc -o name | rg -n 'grafana'  # pick the grafana service name
    2. kubectl -n monitoring port-forward svc/<grafana-svc> 3000:80
    2. Fetch admin user/pass from secret grafana-admin and call Grafana search API
  Expected: dashboard titles returned (Velero + MinIO)
  Evidence: .sisyphus/evidence/phase5-grafana/search.json
```

---

### 5) Alert routing: choose Prometheus/Alertmanager vs Grafana Unified Alerting

**What to do**
- Implement **Grafana Unified Alerting provisioning** for backup alerts.
- Create 1+ ConfigMaps in namespace `monitoring` labeled `grafana_alert="1"` defining rule groups (YAML `apiVersion: 1` with `groups:`).
- Rules should query the Prometheus datasource; executor must discover the Prometheus datasource UID (Grafana) and use it as `datasourceUid`.
- Keep Task 3 PrometheusRule as canonical PromQL expressions; Grafana alert rules should reuse the same expressions.

**Must NOT do**
- No manual creation of alert rules in UI.

**Recommended agent profile**
- Category: `unspecified-high`
- Skills: `grafana`

**Parallelization**: YES (Wave 2)

**References**
- Grafana contact points provisioning exists: `modules/kubenix/monitoring/grafana-admin.enc.nix` (ConfigMap labeled `grafana_alert=1`).

**Acceptance criteria (agent-executable)**
- Grafana API shows the provisioned alert rule group(s) exist.
- At least one alert is verifiably firing in a controlled test (temporary low threshold), and notification delivery is verifiable (receiver logs OR Grafana alert state).

**QA scenarios**
```
Scenario: Controlled alert fires
  Tool: Bash (kubectl + curl)
  Steps:
    1. Temporarily set MinIO capacity alert threshold to >0 and apply via manifests pipeline
    2. Verify alert is firing via Grafana alert API (preferred) and/or Prometheus /api/v1/alerts
    3. Revert threshold back to >85
  Expected: alert appears FIRING during test window; returns to normal after revert
  Evidence: .sisyphus/evidence/phase5-alerts/firing.json
```

---

## Decisions (resolved)

1) **MinIO metrics authentication (Pi)**: **Public on LAN**

2) **Alert routing**: **Grafana Unified Alerting provisioning**

---

## Post-change validation checklist (run after deploy)

1. Build + render:
```bash
make manifests
```

2. Targets UP (Prometheus):
- Velero target health == up
- MinIO target health == up

3. Metrics present:
- Velero: `velero_backup_attempt_total` (or other velero_backup_* metric)
- MinIO: `minio_cluster_capacity_usable_total_bytes` and `_free_bytes`

4. Rules loaded:
- `/api/v1/rules` contains all new alert names

5. Dashboards visible:
- Grafana search API finds Velero + MinIO dashboards

6. Controlled-fire test:
- prove at least 1 alert can transition to FIRING and be observed via API

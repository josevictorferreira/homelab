# Backup Hub (Pi MinIO) — Phase 1 Identity & Access

## TL;DR

Make Pi MinIO a deterministic “backup hub”: create 4 buckets, 4 static per-service creds (SOPS), bucket-scoped policies, boot-only `mc` bootstrap; lock ports 9000/9001 to LAN only.

**Deliverables**
- Pi MinIO ports 9000/9001 reachable only via LAN iface `end0` (10.10.10.0/24 intent)
- Buckets: `homelab-backup-{velero,postgres,rgw,etcd}`
- Host SOPS secrets for per-service access keys (and materialized `/run/secrets/*`)
- `minio-bootstrap` systemd oneshot (boot-only) provisions/repairs MinIO I&A

**Effort**: Short
**Parallel**: Mostly sequential (firewall+secrets+bootstrap are coupled)
**Critical path**: secrets → bootstrap unit → deploy → verify

---

## Context

Original request: “Phase 1 Foundation (Backup Hub) → Identity & Access only; Pi MinIO already developed.”

Known repo reality
- Pi node: `lab-pi-bk` IP `10.10.10.209` iface `end0` (see `config/nodes.nix`)
- MinIO is enabled via `services.minioCustom` and root creds are `/run/secrets/minio_credentials`
  - module: `modules/services/minio.nix`
  - profile: `modules/profiles/backup-server.nix`
  - host secrets: `secrets/hosts-secrets.enc.yaml` + sops-nix (`modules/common/sops.nix`)

Security gotcha
- `modules/profiles/nixos-server.nix` sets `networking.firewall.enable = false` (Pi has role `nixos-server`), so LAN-only restriction requires an explicit override on Pi.

---

## Work objectives

### Core objective
Declarative MinIO I&A on Pi: buckets + policies + static creds from SOPS; safe to rerun; no data deletion.

### Scope
IN
- Pi MinIO only: bucket+policy+creds provisioning, firewall exposure
OUT
- Velero / rclone / postgres jobs (later phases)
- Any Ceph / k8s changes

Guardrails
- NEVER delete buckets/objects (`mc rb`, `mc rm --recursive` forbidden)
- NEVER embed secrets in Nix store; read from `/run/secrets/*` at runtime only
- Bootstrap runs **boot-only** to avoid rotating keys mid-backup

---

## Verification strategy (agent-executed)

No “user verify”. Executor must run commands + capture evidence.

Primary tools
- `make check` / `make ddeploy` / `make deploy`
- `ssh root@10.10.10.209` for on-host checks
- `curl` from another LAN node

Evidence dir
- `.sisyphus/evidence/backup-hub/` (logs, command output)

---

## TODOs

### 1) Fix firewall ownership + scope for MinIO ports

**Recommended agent**: category `quick`, skills `writing-nix-code`

**What to do**
- Ensure Pi firewall is actually enabled (override `nixos-server` default): set `networking.firewall.enable = true` in Pi context (prefer `backup-server` profile with `lib.mkForce true`).
- Stop opening MinIO ports globally from the service module:
  - edit `modules/services/minio.nix` to remove `networking.firewall.allowedTCPPorts = [ 9000 9001 ];`
- Open MinIO ports on LAN only via interface scoping in `modules/profiles/backup-server.nix`:
  - `networking.firewall.interfaces.end0.allowedTCPPorts = [ 9000 9001 ];`
  - keep existing NFS ports allowances as-is (or also scope them to end0 if desired).

**Must NOT do**
- Don’t expose MinIO on tailscale interface.
- Don’t add 9000/9001 to global `allowedTCPPorts`.

**References**
- `modules/services/minio.nix` (currently opens 9000/9001 globally)
- `modules/profiles/nixos-server.nix` (firewall disabled)
- `config/nodes.nix` (`lab-pi-bk` iface `end0`)

**Acceptance criteria (agent runs)**
- `make check` passes
- After deploy, on Pi:
  - `nft list ruleset > .sisyphus/evidence/backup-hub/nft-ruleset.txt`
  - `.sisyphus/evidence/backup-hub/nft-ruleset.txt` contains allow for 9000/9001 on `iifname "end0"`
- From LAN node (ex: `lab-alpha-cp`):
  - `curl -sf http://10.10.10.209:9000/minio/health/live`

**QA scenarios**
Scenario: MinIO reachable via LAN only
  Tool: Bash (ssh + curl)
  Steps:
    1. From a LAN host, `curl -sf http://10.10.10.209:9000/minio/health/live` → expect 200
    2. On Pi, capture `nft list ruleset` excerpt proving interface-scoped allow
  Evidence: `.sisyphus/evidence/backup-hub/firewall-nft.txt`

---

### 2) Add per-service MinIO creds to host SOPS + materialize as `/run/secrets/*`

**Recommended agent**: category `quick`, skills `writing-nix-code`

**What to do**
- Add 8 keys to `secrets/hosts-secrets.enc.yaml` (SOPS):
  - `minio_velero_access_key_id`, `minio_velero_secret_access_key`
  - `minio_postgres_access_key_id`, `minio_postgres_secret_access_key`
  - `minio_rgw_access_key_id`, `minio_rgw_secret_access_key`
  - `minio_etcd_access_key_id`, `minio_etcd_secret_access_key`
- Values format (default):
  - access key id: 20 chars `[A-Z0-9]` random
  - secret access key: 40 chars `[A-Za-z0-9]` random
- Declare these as sops-nix secrets on Pi (prefer in `modules/profiles/backup-server.nix` so Pi-only):
  - `sops.secrets.<key>.mode = "0400"`
  - owner root (bootstrap runs as root)

**Edit recommendation**
- Use `make secrets` to edit `secrets/hosts-secrets.enc.yaml`.
- If you prefer non-interactive: use `sops` CLI to insert generated values.

**References**
- `modules/common/sops.nix` (sops-nix default file = `secrets/hosts-secrets.enc.yaml`)
- `secrets/hosts-secrets.enc.yaml` (already contains `minio_credentials`)

**Acceptance criteria**
- On Pi after deploy: all files exist:
  - `/run/secrets/minio_velero_access_key_id` etc (8 files)
- Permissions:
  - `stat -c '%a %U %G' /run/secrets/minio_velero_access_key_id` == `400 root root`

**QA scenario**
Scenario: Secrets materialized
  Tool: Bash (ssh)
  Steps:
    1. `ls -l /run/secrets/minio_*_access_key_id /run/secrets/minio_*_secret_access_key`
    2. `stat ...` verify mode/owner
  Evidence: `.sisyphus/evidence/backup-hub/run-secrets.txt`

---

### 3) Ensure `mc` is present on the Pi

**Recommended agent**: category `quick`, skills `writing-nix-code`

**What to do**
- Add `pkgs.minio-client` to Pi profile packages (`modules/profiles/backup-server.nix`).

**Acceptance criteria**
- On Pi: `command -v mc` returns path; `mc --version` works

---

### 4) Add `minio-bootstrap` systemd oneshot (boot-only) to provision I&A

**Recommended agent**: category `unspecified-low`, skills `writing-nix-code`

**What to do**
- In `modules/profiles/backup-server.nix`, define `systemd.services.minio-bootstrap`:
  - `Type=oneshot`, `RemainAfterExit=true`
  - `After=minio.service zpool-import-backup.service network-online.target`
  - `Requires=minio.service zpool-import-backup.service`
  - `WantedBy=multi-user.target`
  - `EnvironmentFile=/run/secrets/minio_credentials`
  - `RuntimeDirectory=minio-bootstrap`
  - `Environment=MC_CONFIG_DIR=/run/minio-bootstrap`
  - Talk to localhost only: `http://127.0.0.1:9000`
- Script logic (idempotent; non-destructive):
  1. Wait loop until MinIO ready (pick one):
     - `curl -sf http://127.0.0.1:9000/minio/health/ready` retry, OR
     - `MC_HOST_pi=... mc admin info pi` retry
  2. Set admin host env (NO alias file needed):
     - `export MC_HOST_pi="http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@127.0.0.1:9000"`
  3. For each bucket `homelab-backup-{velero,postgres,rgw,etcd}`:
     - `mc mb pi/<bucket> --ignore-existing` (or ignore error)
     - Ensure ILM expiry 14d (rule id `expire-14d`; confirm exact flags via `mc ilm rule add --help`)
      - If `mc ilm` requires versioning in your MinIO version: `mc version enable pi/<bucket>` then apply ILM.
  4. For each service creds pair from `/run/secrets/minio_<svc>_{access_key_id,secret_access_key}`:
     - Build policy JSON (same actions, bucket-scoped)
     - Enforce drift by rotation:
       - remove user (ignore if missing)
       - add user with desired secret
     - attach policy

**Hardening**
- Ensure the unit/script does NOT log secrets:
  - no `set -x`
  - never `echo $MC_HOST_pi` / creds
  - write only high-level progress to journal

**Policy action set (same for all, bucket-limited)**
- Bucket ARN: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:ListBucketMultipartUploads`
- Object ARN: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`

**Must NOT do**
- No bucket deletion.
- No object deletion beyond what apps do later.

**References**
- `modules/profiles/backup-server.nix` (already orders minio after zpool import)
- NixOS MinIO creds file format: `/run/secrets/minio_credentials` is EnvironmentFile (`MINIO_ROOT_USER/MINIO_ROOT_PASSWORD`)

**Acceptance criteria**
- On Pi:
  - `systemctl status minio-bootstrap` is success
  - `journalctl -u minio-bootstrap --no-pager` shows buckets created + policies attached
  - `MC_HOST_pi=... mc ls pi/` lists all 4 buckets
  - `mc ilm rule ls pi/<bucket>` shows expiry rule (14d)
  - For each access key id: `mc admin user info pi <accessKeyId>` succeeds

**QA scenarios**
Scenario: Bootstrap provisions state
  Tool: Bash (ssh)
  Steps:
    1. `ssh root@10.10.10.209 'systemctl start minio-bootstrap'`
    2. `ssh root@10.10.10.209 'journalctl -u minio-bootstrap --no-pager' | tee .sisyphus/evidence/backup-hub/minio-bootstrap.log`
    3. `ssh root@10.10.10.209 'set -a; . /run/secrets/minio_credentials; set +a; export MC_HOST_pi="http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@127.0.0.1:9000"; mc ls pi/'`
  Evidence: `.sisyphus/evidence/backup-hub/minio-bootstrap.log`

---

### 5) Deploy + validate end-to-end

**Recommended agent**: category `quick`, skills `writing-nix-code`

**What to do**
- Ensure new/changed files are staged before flake eval (repo rule).
- Run:
  - `make check`
  - `make ddeploy` (select `lab-pi-bk`)
  - `make deploy` (select `lab-pi-bk`)

**Acceptance criteria**
- `make check` PASS
- deploy PASS
- Pi checks from TODOs 1-4 all PASS

---

## Commit strategy

Recommend 1 commit (Phase1 only):
- `feat(backup-hub): minio I&A bootstrap + lan-only firewall`

Files likely touched
- `modules/services/minio.nix`
- `modules/profiles/backup-server.nix`
- `secrets/hosts-secrets.enc.yaml`

---

## Success criteria

- Pi exposes MinIO API+console only on LAN interface
- `minio-bootstrap` converges Pi MinIO to desired state on every boot
- Buckets exist + ILM 14d present + per-service creds usable

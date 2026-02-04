# Blocky + Tailscale DNS (tailnet clients + MagicDNS forward)

## TL;DR

Make tailnet clients (with subnet route to `10.10.10.0/24`) use **Blocky @ 10.10.10.100**, and make Blocky resolve **MagicDNS zone `tail96fefe.ts.net`** by conditional-forwarding that zone to **unbound forwarders on the Tailscale subnet-router nodes** (alpha/beta) which forward upstream to **`100.100.100.100`**.

**Deliverables**
- Blocky `config.yml`: add `conditional.mapping` for `tail96fefe.ts.net` → `10.10.10.200:1053,10.10.10.201:1053`
- NixOS: enable/configure `unbound` on subnet routers (alpha+beta) to forward `tail96fefe.ts.net` → `100.100.100.100`
- Agent-run verification: `dig` from in-cluster + from router nodes
- Optional fallback: expose Blocky over tailnet (100.x) if subnet routes not reliable

**Estimated Effort**: Medium
**Parallel Execution**: YES (blocky config + unbound config)
**Critical Path**: unbound forwarders → blocky conditional forward → verify

---

## Context

### Original ask
Add Tailscale “sidecar” to Blocky so tailnet can use Blocky as custom nameserver.

### What we’re doing instead (simpler, matches your setup)
- You already run Tailscale on NixOS nodes, with subnet routing.
- Tailnet clients will use Blocky via **LAN LB IP 10.10.10.100** (no k8s-sidecar needed).
- Blocky will resolve MagicDNS suffix by conditional forward.

### Repo references (verified)
- Blocky app: `modules/kubenix/apps/blocky.nix` (Helm app-template), replicas=3, DNS exposed via LB on UDP/TCP 53
- Blocky config: `modules/kubenix/apps/blocky-config.enc.nix` (ConfigMap `blocky`, `data.config.yml`)
- LB IPs: `config/kubernetes.nix` (`blocky = "10.10.10.100"`)
- Node roles: `config/nodes.nix` (alpha+beta have `tailscale-router`)
- Tailscale config: `modules/profiles/tailscale.nix` (`--advertise-routes=10.10.10.0/24`, `--accept-dns=true` when router)

### Note: Metis
Metis tool call failed (infra error). Plan includes explicit guardrails + self-review checklist.

---

## Work objectives

### Core objective
1) Tailnet clients can use Blocky at `10.10.10.100` for DNS.
2) Queries under `tail96fefe.ts.net` resolve via Tailscale MagicDNS.

### Scope boundaries
IN
- Blocky conditional forwarding config
- NixOS unbound forwarders on alpha+beta
- k8s/host verification commands

OUT
- Changing `.k8s/` directly (generated)
- Any Ceph/rook changes

---

## Verification strategy (MANDATORY: agent-executable)

**No unit test infra expected** (infra/config change). Verification is runtime checks.

**Precondition / automation choice**
- Tailnet-wide “custom nameserver” setting lives in Tailscale admin.
- For strict agent-only verification, either:
  - Provide Tailscale Admin API key + tailnet name so agent can set DNS prefs via API, OR
  - Treat “tailnet DNS points to 10.10.10.100” as a precondition (agent verifies only infra + resolution, not admin setting).
- `make check` (flake)
- `make manifests` (kubenix render pipeline)
- Deploy NixOS to alpha+beta (group deploy)
- Verify DNS flows with `dig` using `kubectl` + `ssh`

**Evidence**
- Save `dig` outputs to `.sisyphus/evidence/` (stdout capture)

---

## Execution strategy

Wave 1 (parallel)
- Task 1: Unbound forwarders on routers
- Task 2: Blocky conditional forward config

Wave 2
- Task 3: Deploy + runtime verification

Wave 3 (optional)
- Task 4: Fallback (tailnet-exposed Blocky) if subnet routes not reliable

---

## TODOs

### 1) Configure unbound forwarders on subnet routers (alpha+beta)

**What to do**
- Implement unbound on nodes with role `tailscale-router` (alpha=10.10.10.200, beta=10.10.10.201).
- Listen on **UDP+TCP 1053** on LAN.
- Forward-zone: `tail96fefe.ts.net.` → `100.100.100.100@53`.
- Access-control allow at least:
  - `10.10.10.0/24` (nodes)
  - k8s pod CIDRs seen in repo: `10.42.0.0/16`, `10.43.0.0/16`

**Repo constraint**
- `modules/profiles/nixos-server.nix` has `networking.firewall.enable = false` (so firewall rules may be moot). Still enforce access via unbound `access-control`.

**Guardrails**
- Do NOT forward via system resolv.conf (avoid loops when tailnet DNS points to Blocky). Use explicit `forward-addr`.
- Do NOT bind port 53 on routers (avoid conflicts).

**Recommended Agent Profile**
- Category: unspecified-high (NixOS services)
- Skills: writing-nix-code

**Parallelization**: YES (with Task 2)

**References**
- `config/nodes.nix` (tailscale-router on alpha/beta)
- `modules/profiles/tailscale.nix` (router detection `builtins.elem "tailscale-router" hostConfig.roles`)
- `modules/profiles/tailscale-router.nix` (marker role)
- Blocky docs conditional forwarding (for loop considerations): https://0xerr0r.github.io/blocky/latest/configuration/#conditional-dns-resolution

**Implementation note (NixOS)**
- No existing unbound usage found in repo; use NixOS built-in `services.unbound` (new config in an existing profile, likely `modules/profiles/tailscale.nix` under `isRouter`).

**Acceptance criteria (agent-executable)**
- Stage new/changed files before `make check` (flake uses git state)
- `make check` succeeds
- After deploying to alpha+beta:
  - `ssh josevictor@10.10.10.200 "sudo ss -lunpt | grep ':1053'"` shows unbound listening UDP+TCP 1053
  - `ssh josevictor@10.10.10.201 "sudo ss -lunpt | grep ':1053'"` shows same
  - `ssh josevictor@10.10.10.200 "tailscale status --json | jq -r .MagicDNSSuffix"` = `tail96fefe.ts.net`
  - `ssh josevictor@10.10.10.200 "HN=$(tailscale status --json | jq -r .Self.DNSName | sed 's/\\.$//'); dig +short @127.0.0.1 -p 1053 $HN"` returns `100.x` IP
  - `ssh josevictor@10.10.10.201 "HN=$(tailscale status --json | jq -r .Self.DNSName | sed 's/\\.$//'); dig +short @127.0.0.1 -p 1053 $HN"` returns `100.x` IP

**QA scenarios**
Scenario: Router unbound forwards MagicDNS
  Tool: ssh + dig
  Steps:
    1. ssh to alpha
    2. `HN=$(tailscale status --json | jq -r .Self.DNSName | sed 's/\\.$//')`
    3. `dig +short @127.0.0.1 -p 1053 $HN`
    3. Assert: output is non-empty and matches `100.` prefix
  Evidence: `.sisyphus/evidence/task-1-alpha-dig.txt`

Scenario: Unknown host under tail96fefe.ts.net returns NXDOMAIN (no fallback leakage)
  Tool: ssh + dig
  Steps:
    1. ssh alpha
    2. `dig @127.0.0.1 -p 1053 definitely-does-not-exist.tail96fefe.ts.net +comments`
    3. Assert: `status: NXDOMAIN` (or empty answer with NXDOMAIN)
  Evidence: `.sisyphus/evidence/task-1-alpha-nxdomain.txt`

---

### 2) Add Blocky conditional forward for MagicDNS zone

**What to do**
- Update `modules/kubenix/apps/blocky-config.enc.nix` to include:
  - `conditional.mapping.tail96fefe.ts.net = "tcp+udp:10.10.10.200:1053,tcp+udp:10.10.10.201:1053"`
  - Keep `conditional.fallbackUpstream = false` (default) to avoid leaking internal queries to public upstreams.

**Blocky format confirmation**
- Docs/examples allow comma-separated resolvers in `conditional.mapping`, and upstream strings support `[net:]host:[port]` (so `tcp+udp:10.10.10.200:1053,...` is valid).

**Guardrails**
- Do NOT change existing `upstreams.groups.default = homelab.dnsServers`.
- Do NOT touch `.k8s/`.

**Recommended Agent Profile**
- Category: quick
- Skills: writing-nix-code

**Parallelization**: YES (with Task 1)

**References**
- `modules/kubenix/apps/blocky-config.enc.nix` (current `blockyConfig` attrset → YAML)
- Blocky docs conditional DNS: https://0xerr0r.github.io/blocky/latest/configuration/#conditional-dns-resolution

**Acceptance criteria (agent-executable)**
- Stage new/changed files before `make manifests` (flake uses git state)
- `make manifests` completes
- Rendered Blocky config in generated manifests contains `conditional:` with mapping for `tail96fefe.ts.net`

**QA scenarios**
Scenario: In-cluster pod resolves MagicDNS via Blocky
  Tool: kubectl
  Preconditions: Blocky pods running; unbound deployed on routers
  Steps:
    1. `kubectl -n apps get svc -o wide | grep -i blocky` confirms a LB with EXTERNAL-IP `10.10.10.100` on UDP/TCP 53
    2. `HN=$(ssh josevictor@10.10.10.200 "tailscale status --json | jq -r .Self.DNSName | sed 's/\\.$//'")`
    2. Run a dnsutils pod and execute:
       - `dig +short @10.10.10.100 $HN`
    3. Assert: returns `100.x` IP
  Evidence: `.sisyphus/evidence/task-2-k8s-dig.txt`

---

### 3) Deploy + end-to-end verification

**What to do**
- Deploy NixOS changes to alpha+beta (they are control-plane nodes).
- Let Flux reconcile k8s (or run `make reconcile`).
- Verify:
  - From k8s: `dig @10.10.10.100` resolves MagicDNS zone
  - From routers: direct `dig -p 1053` works

**Recommended Agent Profile**
- Category: unspecified-high
- Skills: kubernetes-tools, writing-nix-code

**References**
- `Makefile` targets: `make gdeploy`, `make kubesync`, `make reconcile`, `make manifests`

**Non-interactive deploy commands (agent-safe; avoids fzf prompts in Makefile)**
- Deploy just alpha+beta:
  - `nix run github:serokell/deploy-rs -- --auto-rollback true .#lab-alpha-cp .#lab-beta-cp -- --impure --show-trace`
- If you prefer group deploy (control plane), note `make gdeploy` is interactive; use:
  - `targets=$(nix eval --raw .#deployGroups.k8s-control-plane)`
  - `nix run github:serokell/deploy-rs -- --skip-checks --auto-rollback true $targets`

**Acceptance criteria (agent-executable)**
- NixOS deploy to alpha+beta completes with auto-rollback enabled (using commands above)
- `make manifests` then commit-ready tree
- `kubectl -n apps get pods -l app.kubernetes.io/name=blocky` shows Ready replicas
- `kubectl` dig scenario in Task 2 passes

**QA scenario**
Scenario: Blocky pods are running config with conditional mapping
  Tool: kubectl
  Steps:
    1. `kubectl -n apps get configmap blocky -o jsonpath='{.data.config\\.yml}' | grep -F 'tail96fefe.ts.net'` succeeds
    2. If Blocky pods don’t reload after reconcile, run `kubectl -n apps rollout restart deploy -l app.kubernetes.io/name=blocky` then wait Ready
  Evidence: `.sisyphus/evidence/task-3-configmap.txt`

---

### 4) OPTIONAL fallback: expose Blocky DNS over tailnet (no subnet routes)

Trigger: some tailnet clients can’t / won’t accept subnet routes.

**Option A (recommended for fallback)**
- Add Tailscale Kubernetes Operator and expose Blocky Service over tailnet.

**Option B**
- Add manual tailscaled sidecar to Blocky chart values and expose port 53 over tailnet; likely requires stable identity (StatefulSet or single replica).

**References**
- Sidecar pattern: `modules/kubenix/apps/qbittorrent.nix` (gluetun addon)

---

## Optional: automate Tailscale DNS preference

Tailnet-wide “custom nameserver” is set in Tailscale admin.

If you want this change itself to be agent-executable, add an extra task to:
- store a Tailscale Admin API key in SOPS, and
- call the Admin API to set nameserver=10.10.10.100 (and enable MagicDNS as desired).

Otherwise, treat “tailnet DNS points to 10.10.10.100” as a precondition; plan still verifies the infra + resolution paths.

---

## Success criteria

- From a tailnet-connected host that has subnet route to `10.10.10.0/24` (alpha/beta qualify), this works:
  - `dig +short @10.10.10.100 $(tailscale status --json | jq -r .Self.DNSName | sed 's/\\.$//')` returns `100.x`
- From a k8s dnsutils pod: same query returns `100.x`
- No DNS loop observed (unbound uses explicit upstream 100.100.100.100, Blocky fallbackUpstream remains false)

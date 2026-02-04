# Draft: Tailscale sidecar for Blocky (DNS + tailnet)

## Goal (as requested)
- Add Tailscale in k8s as a sidecar to the Blocky pod, so Tailscale can be used as a custom nameserver for the Blocky network.

## Interpretation (current)
- We’re pivoting from “Blocky sidecar” to “node-level tailscale already exists”:
  - Tailnet clients reach Blocky via subnet route to `10.10.10.100`.
  - Blocky resolves MagicDNS suffix `tail96fefe.ts.net` via conditional forward to a forwarder running on subnet-router nodes.

## Tailscale/DNS control-plane gap
- Setting tailnet-wide DNS nameserver (Blocky) happens in Tailscale admin (SaaS).
- If we must keep the plan 100% agent-executable (no human clicks), we likely need to automate via Tailscale Admin API (needs API key secret).

## What I think you might mean (needs confirmation)
- Option A: Blocky should resolve tailnet/MagicDNS names by forwarding specific zones to Tailscale DNS (e.g., MagicDNS at 100.100.100.100), which requires Blocky to have tailnet connectivity.
- Option B: Tailnet clients should use Blocky as the DNS server (custom nameserver in Tailscale admin), requiring Blocky to be reachable from tailnet (often via Tailscale sidecar / operator).

## Constraints / context (known)
- Repo: NixOS + kubenix-generated k8s manifests; apps live under modules/kubenix/apps/; secrets via SOPS + vals.

## Research findings (repo)
- Blocky app definition: `modules/kubenix/apps/blocky.nix` (Helm `bjw-s/app-template` via `modules/kubenix/_submodules/release.nix`).
- Blocky config: `modules/kubenix/apps/blocky-config.enc.nix` (ConfigMap data `config.yml`).
- Blocky LB IP assignment: `config/kubernetes.nix` (blocky = `10.10.10.100`).
- Sidecar pattern in repo: `modules/kubenix/apps/qbittorrent.nix` (+ `gluetun-vpn-credentials.enc.nix`).
- No existing Tailscale-in-k8s module under `modules/kubenix/**` (Tailscale exists only as host-level profile: `modules/profiles/tailscale.nix`).

## Research findings (design options)
### Option 1: Tailnet clients use Blocky as DNS ("custom nameserver" in Tailscale)
- Run `tailscaled` in Blocky pod (operator-injected sidecar or manual sidecar) so the *pod* has tailnet connectivity.
- Configure Tailscale admin DNS → Nameservers: use the Blocky pod’s Tailscale IP(s) on port 53 (UDP+TCP).
- With Blocky replicas=3, you’ll likely register 3 tailnet devices; can list all 3 as nameservers for redundancy.

### Option 2: Blocky resolves tailnet names (Blocky → Tailscale DNS upstream)
- Configure Blocky to forward tailnet zones to Tailscale DNS (commonly `100.100.100.100` for MagicDNS) so LAN clients using Blocky can resolve tailnet names.
- This does NOT automatically make Blocky reachable from tailnet; it just improves resolution for tailnet domains.

### Operator vs manual sidecar
- Operator: manages auth/lifecycle; can expose k8s Services over tailnet; less bespoke wiring.
- Manual sidecar: add extra container via app-template `values.controllers.main.containers.<name>` in `blocky.nix`; manage auth key + state volume yourself.

## Research findings (Blocky config keys)
- Blocky supports conditional forwarding via `conditional.mapping` in `config.yml`.
  - Examples from public configs show values like `udp:IP`, `tcp+udp:IP`, or `svc.cluster.local:53`.
  - This maps nicely to: `<tailnet>.ts.net` → `tailscale-dns.<ns>.svc.cluster.local:53`.

## Open Questions
- Which direction is correct: A (Blocky → Tailscale upstream) or B (Tailnet → Blocky nameserver)?
- Do you want to use Tailscale Kubernetes Operator, or strictly a raw sidecar in the Blocky Deployment?
- Auth method allowed for the pod: reusable auth key in SOPS, or OAuth client flow (preferred for long-lived)?
- Any specific tailnet domain(s) to forward (e.g., *.ts.net, tailnet name), or “all internal names”? 
- Keep Blocky replicas at 3 (multiple tailnet DNS endpoints) or force 1 replica for a single stable DNS endpoint?

## Still unknown / needs confirmation
- MagicDNS suffix (exact): `<tailnet>.ts.net` value to forward.
- Subnet route reliability: do all tailnet clients that should use Blocky actually accept routes to `10.10.10.0/24`?

## Fallback path (requested)
- If subnet routes are not reliably enabled on tailnet clients, plan should include an optional alternative:
  - Expose Blocky DNS over tailnet (100.x) so clients can use it without LAN routes.
  - Implementation options: (a) Tailscale Operator Service exposure, or (b) manual tailscaled sidecar with stable identity (likely StatefulSet or single replica).

## Decisions (confirmed)
- Direction: Tailnet clients will use Blocky as DNS (Tailscale custom nameserver).
- Tailscale in k8s: prefer Tailscale Kubernetes Operator.
- Blocky replicas: keep 3 (HA); accept multiple tailnet DNS endpoints.

## New decisions (confirmed)
- Tailnet clients reach Blocky DNS via LAN LB IP `10.10.10.100` (via subnet routes), not via a tailnet-only 100.x IP.
- Blocky should resolve tailnet/MagicDNS names by forwarding relevant zones to Tailscale DNS.

## Updated decisions (confirmed)
- `tailscale-dns` design: separate small k8s app (NOT a Blocky sidecar), exposing UDP+TCP 53 via ClusterIP.
- No Tailscale Kubernetes Operator (minimal manifests only).
- Tailscale auth for `tailscale-dns`: reusable auth key stored via SOPS/vals.
- Tailscale admin DNS: set Blocky (10.10.10.100) as global nameserver for tailnet clients.
- Blocky conditional forward zone: `<tailnet>.ts.net` → `tailscale-dns`.

## Updated (supersedes tailscale-dns pod)
- Tailscale already on NixOS nodes; do tailnet DNS forwarding on subnet-router nodes (not in k8s).
- MagicDNS suffix to forward: `tail96fefe.ts.net`.
- Blocky conditional mapping should forward `tail96fefe.ts.net` → node forwarder(s) (alpha/beta LAN IPs).

## Node forwarder details (confirmed)
- Forwarder: unbound on lab-alpha-cp (10.10.10.200) and lab-beta-cp (10.10.10.201)
- Listen: UDP+TCP 1053 on LAN
- Upstream: Tailscale MagicDNS resolver `100.100.100.100`
- Firewall: open 1053/udp+tcp on LAN (at least reachable from k8s pods). In-cluster CIDRs seen in repo: `10.42.0.0/16`, `10.43.0.0/16`.

## Success criteria (draft)
- Blocky can resolve tailnet names as intended OR tailnet clients can use Blocky as DNS (depending on chosen option), with repeatable, agent-executable verification steps.

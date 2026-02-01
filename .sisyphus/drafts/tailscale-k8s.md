# Draft: Tailscale for homelab k3s (Cilium, NixOS)

## Core objective (from user)
- Add Tailscale to cluster/homelab so you can access:
  - LAN devices
  - homelab machines
  - from outside

## Requirements (confirmed)
- Primary outcomes (first):
  - Access LAN subnets via Tailscale
  - Expose selected k8s services (details TBD: via existing ingress/LB vs Tailscale operator)
- Preferred placement: host-level Tailscale on NixOS nodes
- Redundancy: 2 subnet routers (active/active)

## Constraints / context
- k3s Kubernetes
- Cilium CNI
- Hosts are NixOS (use nixpkgs tailscale module)
- GitOps-ish repo: kubenix generates manifests; secrets via SOPS (per AGENTS.md)

## Candidate approaches (to decide)
1) **Host-level Tailscale on NixOS nodes** (selected as primary)
   - Each node joins tailnet (SSH/admin)
   - 1+ nodes advertise subnet route(s) (LAN / maybe k8s CIDRs)
   - Optional exit node

2) **Kubernetes-level Tailscale** (operator / sidecars)
   - Expose specific Services to tailnet
   - Optional APIServer proxy
   - Optional subnet router pod

## Redundancy note
- Subnet routes can be advertised from >1 router node for failover; need to confirm preferred behavior + which nodes.

## Open questions
- For “expose selected k8s services”: is existing LAN ingress/VIP enough (reachable via LAN subnet route), or do you want per-Service Tailscale names via operator?
- Which LAN subnets to advertise (CIDRs)?
- Need exit node (0.0.0.0/0, ::/0) or only LAN reachability?
- Which 2 nodes should run subnet routing (for redundancy)?
- Auth model: ephemeral + reusable auth keys? device approval on/off?
- DNS: use MagicDNS / tailnet DNS? split DNS for homelab domain?
- Firewall posture: accept Tailscale’s default ts-input behavior or force nodivert?

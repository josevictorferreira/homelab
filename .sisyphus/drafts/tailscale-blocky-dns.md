# Draft: Tailscale clients use Blocky DNS (+ MagicDNS resolution)

## Requirements (stated)
- Configure tailnet clients to use Blocky as DNS nameserver.
- Blocky must resolve tailnet/MagicDNS names too.

## Requirements (confirmed)
- Main path: tailnet clients reach Blocky via Tailscale subnet routes (no k8s Tailscale).
- MagicDNS zone: `tail96fefe.ts.net`
- Forwarder: unbound on subnet-router nodes; Blocky conditional-forward the MagicDNS zone to unbound.

## Decisions (confirmed)
- Tailscale DNS mode: Admin console "Override local DNS" ON; tailnet nameserver = Blocky (10.10.10.100).
- unbound ACL allow-list: assume k3s defaults: Pod `10.42.0.0/16`, Service `10.43.0.0/16`, plus LAN `10.10.10.0/24`.
- Fallback path: later-only (do not include tailnet-exposed Blocky DNS in main plan).

## Implementation Anchors (repo)
- Blocky app: `modules/kubenix/apps/blocky.nix`
- Blocky config: `modules/kubenix/apps/blocky-config.enc.nix` (ConfigMap `configMaps."blocky"`, key `data."config.yml"`)
- LB IP registry: `config/kubernetes.nix` (`loadBalancer.services.blocky = "10.10.10.100"`)
- LB helper: `modules/kubenix/_lib/default.nix` (`serviceAnnotationFor`)
- Tailscale profile: `modules/profiles/tailscale.nix` (router detection `builtins.elem "tailscale-router" hostConfig.roles`)
- Router marker profile: `modules/profiles/tailscale-router.nix`
- Firewall default: `modules/profiles/nixos-server.nix` (`networking.firewall.enable = false`)

## Tailnet Admin Step (confirmed: manual)
- Configure in Tailscale admin UI (no API key automation).

## Proposed Approach (needs confirmation)
1) Keep Tailscale on NixOS nodes (no k8s sidecar/operator initially).
2) Tailnet clients reach Blocky via LAN IP (Blocky LB service, `10.10.10.100`) over subnet routing.
3) Run unbound on subnet-router nodes (alpha/beta) listening on LAN `:1053` (UDP+TCP).
4) unbound forwards only `tail96fefe.ts.net.` to `100.100.100.100` (MagicDNS).
5) Blocky config: `conditional.mapping."tail96fefe.ts.net" = "tcp+udp:10.10.10.200:1053,tcp+udp:10.10.10.201:1053"`.
6) Guardrail: `conditional.fallbackUpstream = false` for that zone (avoid leaking internal tailnet queries to public resolvers).

## Repo Facts (from AGENTS.md)
- Blocky LB IP is `10.10.10.100`.
- Subnet routers: lab-alpha-cp (10.10.10.200), lab-beta-cp (10.10.10.201).
- Tailscale router role detection: `builtins.elem "tailscale-router" hostConfig.roles`.

## Open Questions
- Tailscale admin DNS mode: set Blocky as tailnet nameserver w/ “Override local DNS”? or split-DNS only?
- Confirm k8s PodCIDR/ServiceCIDR for unbound ACL allow-list (defaults often `10.42.0.0/16` + `10.43.0.0/16` in k3s).
- Any security constraint: allow unbound only from LAN + k8s CIDRs? (no tailnet 100.x direct).
- Need fallback (later): serve Blocky over tailnet 100.x if some clients can’t/shouldn’t accept subnet routes.

## Scope Boundaries
- INCLUDE: NixOS config changes for forwarder + Blocky config changes (kubenix) + verification steps.
- EXCLUDE (default): installing Tailscale operator in k8s unless fallback is requested.

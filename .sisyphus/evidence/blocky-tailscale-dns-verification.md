# Blocky + Tailscale DNS Integration - Evidence

**Date:** 2026-02-04
**Plan:** .sisyphus/plans/blocky-tailscale-dns.md

## Architecture
```
Tailnet Client → Blocky (10.10.10.100) → Unbound (router:1053) → Tailscale MagicDNS (100.100.100.100)
```

## Verification Results

### 1. Unbound Service Status (Both Routers)

**Alpha (10.10.10.200):**
```
$ ss -ulnp | grep 1053
UNCONN 0 0 10.10.10.200:1053 0.0.0.0:*
UNCONN 0 0    127.0.0.1:1053 0.0.0.0:*
$ systemctl is-active unbound
active
```

**Beta (10.10.10.201):**
```
$ ss -ulnp | grep 1053
UNCONN 0 0 10.10.10.201:1053 0.0.0.0:*
UNCONN 0 0    127.0.0.1:1053 0.0.0.0:*
$ systemctl is-active unbound
active
```

### 2. Direct Unbound Test (from local machine)
```
$ dig +short @10.10.10.200 -p 1053 lab-alpha-cp.tail96fefe.ts.net
100.116.138.78
```

### 3. End-to-End via Blocky
```
$ dig +short @10.10.10.100 lab-alpha-cp.tail96fefe.ts.net
100.116.138.78

$ dig +short @10.10.10.100 lab-beta-cp.tail96fefe.ts.net
100.107.122.102

$ dig +short @10.10.10.100 lab-gamma-wk.tail96fefe.ts.net
100.125.181.92
```

## Key Configuration

### tailscale.nix (routers)
- `--accept-dns=false` - prevents Tailscale from managing resolv.conf
- `resolveLocalQueries = false` - unbound doesn't take over system DNS
- Static nameservers: Blocky (10.10.10.100) + fallbacks
- Unbound access-control: `10.0.0.0/16` (Cilium pod CIDR), `10.10.10.0/24` (LAN)

### blocky-config.enc.nix
```nix
conditional = {
  fallbackUpstream = false;
  mapping = {
    "tail96fefe.ts.net" = "tcp+udp:10.10.10.200:1053,tcp+udp:10.10.10.201:1053";
  };
};
```

## Issues Encountered & Fixed

1. **Tailscale DNS loop** - routers pointed to 127.0.0.1 but nothing on :53
   - Fix: `--accept-dns=false` + static nameservers

2. **Unbound resolvconf takeover** - `resolveLocalQueries` enabled by default
   - Fix: Set `resolveLocalQueries = false`

3. **Wrong pod CIDR** - Cilium uses 10.0.0.0/16, not k3s default 10.42.0.0/16
   - Fix: Updated unbound access-control

## Commits
- `63714b5` - feat(dns): blocky conditional forward to unbound for MagicDNS
- `3941a9f` - fix(unbound): correct pod CIDR access-control (10.0.0.0/16)

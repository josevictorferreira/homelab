# Tailscale Integration Plan for Homelab

## Overview
Add Tailscale VPN to the NixOS-based k3s cluster for secure remote access to LAN devices (10.10.10.0/24) and homelab machines.

## Architecture Decision

### Approach: Host-Level NixOS Tailscale (Selected)
- **Why**: Simplest, most reliable for LAN access, no k8s complexity needed
- **Redundancy**: 2 subnet routers (active/active) for failover
- **Scope**: LAN subnet (10.10.10.0/24) only - k8s services reachable via existing ingress/VIP

### Alternative Rejected
- Kubernetes operator: Overkill for LAN access only, adds pod complexity

## Implementation

### 1. New Profile: `modules/profiles/tailscale.nix`
```nix
{ lib, config, pkgs, hostConfig, ... }:

let
  cfg = config.profiles.tailscale;
  isRouter = builtins.elem "tailscale-router" hostConfig.roles;
in
{
  options.profiles.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN";
  };

  config = lib.mkIf cfg.enable {
    # Enable tailscale service
    services.tailscale = {
      enable = true;
      useRoutingFeatures = if isRouter then "server" else "client";
      authKeyFile = config.sops.secrets.tailscale_auth_key.path;
      extraSetFlags = lib.optionals isRouter [
        "--advertise-routes=10.10.10.0/24"
        "--accept-dns=true"
      ];
    };

    # Firewall configuration
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    # Secret for auth key
    sops.secrets.tailscale_auth_key = {
      sopsFile = ../../secrets/k8s-secrets.enc.yaml;
      owner = "root";
      mode = "0400";
    };
  };
}
```

### 2. Update `config/nodes.nix`
Add `tailscale` role to all nodes, `tailscale-router` to alpha and beta:
```nix
lab-alpha-cp.roles = [ ... "tailscale" "tailscale-router" ];
lab-beta-cp.roles = [ ... "tailscale" "tailscale-router" ];
lab-gamma-wk.roles = [ ... "tailscale" ];
lab-delta-cp.roles = [ ... "tailscale" ];
lab-pi-bk.roles = [ ... "tailscale" ];  # Optional
```

### 3. Update Secrets
Add to `secrets/k8s-secrets.enc.yaml`:
```yaml
tailscale_auth_key: tskey-auth-...
```

## Prerequisites (User Action Required)

1. **Generate Auth Key** at https://login.tailscale.com/admin/settings/keys
   - Type: Auth key
   - Reusable: Yes (for multiple nodes)
   - Ephemeral: No (nodes persist)
   - Pre-approved: Yes (if device approval enabled)

2. **Enable Routes in Tailscale Admin Console**
   After deployment, go to Machines page and:
   - Approve the routes advertised by alpha and beta
   - Enable "10.10.10.0/24" for both nodes

3. **Client Configuration**
   On devices connecting to tailnet:
   ```bash
   tailscale up --accept-routes
   ```

## Verification Steps

1. Check tailscale status on each node:
   ```bash
   tailscale status
   ```

2. Verify routes are advertised (on routers):
   ```bash
   tailscale status --json | jq '.Self.PrimaryRoutes'
   ```

3. Test connectivity from outside:
   ```bash
   ping 10.10.10.200  # Should work via tailscale
   curl http://10.10.10.250  # VIP via tailscale
   ```

## Security Considerations

- Auth key stored in SOPS-encrypted secrets
- Firewall allows tailscale0 as trusted interface
- No exit node configured (LAN access only)
- Routes must be manually approved in admin console

## DNS Configuration

Tailscale DNS will be configured to use your internal Blocky DNS (10.10.10.100) as the primary resolver for all tailnet clients.

### Tailscale Admin Console Setup
1. Go to https://login.tailscale.com/admin/dns
2. Under "Nameservers", click "Add nameserver" → "Custom"
3. Add: `10.10.10.100`
4. Enable "Override local DNS" to force all tailnet clients to use this DNS

This ensures:
- All tailnet devices use Blocky for DNS resolution
- Internal homelab domain names resolve correctly
- Ad-blocking/filtering from Blocky applies to tailnet clients

## Future Enhancements (Optional)

- Add exit node capability (0.0.0.0/0) for full VPN
- Enable MagicDNS for tailnet hostnames (if you want `machine.tailnet-name.ts.net` addresses)
- Add Tailscale SSH for node access
- Consider Tailscale Kubernetes operator for specific service exposure

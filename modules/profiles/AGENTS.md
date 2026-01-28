# NIXOS PROFILES

Role-based NixOS modules. Hosts in `config/nodes.nix` declare roles → profiles auto-enabled.

## ROLES → PROFILES

| Role | Profile | Purpose |
|------|---------|---------|
| `k8s-control-plane` | HA k3s server, etcd, HAProxy, Keepalived |
| `k8s-worker` | k3s agent mode |
| `k8s-server` | Common k3s settings (both CP and worker) |
| `k8s-storage` | Ceph kernel modules, LVM |
| `amd-gpu` | ROCm, AMDVLK, GPU drivers |
| `system-admin` | SSH, users, base packages |
| `nixos-server` | Common server settings |
| `backup-server` | Backup services |

## MODULE PATTERN

```nix
{ lib, config, hostConfig, homelab, ... }:

let
  cfg = config.profiles."my-profile";
in
{
  options.profiles."my-profile" = {
    enable = lib.mkEnableOption "My profile";
    # Additional options...
  };

  config = lib.mkIf cfg.enable {
    # Configuration when enabled
  };
}
```

## HOW ROLES WORK

1. Host declares roles in `config/nodes.nix`:
   ```nix
   lab-alpha-cp.roles = [ "k8s-control-plane" "k8s-storage" ... ];
   ```

2. `hosts/default.nix` auto-imports and enables:
   ```nix
   imports = map (r: "${homelab.paths.profiles}/${r}.nix") hostConfig.roles;
   profiles = listToAttrs (map (r: { name = r; value.enable = true; }) hostConfig.roles);
   ```

## K8S CONTROL PLANE SPECIFICS

- First node in group = cluster init (`--cluster-init`)
- Others join via VIP (10.10.10.250)
- Bootstrap manifests only on init node
- Cilium, Flux components deployed via k3s manifests

## IMPORTS

Profiles can import from:
- `${homelab.paths.services}/` - Custom services (haproxy, keepalived)
- `${homelab.paths.common}/` - Shared settings
- `${homelab.paths.programs}/` - Custom programs

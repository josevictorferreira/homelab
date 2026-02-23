# NIXOS PROFILES

Role-based NixOS modules. Hosts declare roles in `config/nodes.nix` → profiles auto-enabled.

## WHERE TO LOOK

| Role | Profile | Purpose |
|------|---------|---------|
| `nixos-server` | Base server config, networking, zram, journal limits | Foundation for all nodes |
| `system-admin` | SSH, users, sops, vim/zsh/git | Admin access and tools |
| `k8s-server` | k3s deps, kernel modules, firewall ports | Common k3s prerequisites |
| `k8s-control-plane` | k3s server, HAProxy, Keepalived, etcd snapshots | Control plane with VIP |
| `k8s-worker` | k3s agent, kubelet GC settings | Worker node |
| `k8s-storage` | Ceph kernel modules, LVM, blacklists `nbd` | Storage node |
| `amd-gpu` | ROCm, AMDVLK, GPU drivers | GPU workloads |
| `tailscale` | VPN mesh, subnet router logic | Remote access |
| `tailscale-router` | Marker role for subnet routing | Detected by `tailscale.nix` |
| `backup-server` | MinIO, ZFS pool, NFS, Wake-on-LAN | Backup target |

## HOW ROLES WORK

1. Host declares roles in `config/nodes.nix`:
   ```nix
   lab-alpha-cp.roles = [ "k8s-control-plane" "k8s-storage" "tailscale-router" ];
   ```

2. `hosts/default.nix` auto-imports and enables:
   ```nix
   imports = map (r: "${homelab.paths.profiles}/${r}.nix") hostConfig.roles;
   profiles = listToAttrs (map (r: { name = r; value.enable = true; }) hostConfig.roles);
   ```

## CONVENTIONS

- **Profile module pattern**: Use `options.profiles."<name">` with `lib.mkEnableOption`
- **Conditional config**: Wrap in `lib.mkIf cfg.enable { }`
- **Marker profiles**: `tailscale-router.nix` has empty config, detected by other profiles
- **Role detection**: Use `builtins.elem "role-name" hostConfig.roles` for conditional logic
- **Imports**: Reference services via `${homelab.paths.services}/<name>.nix`

## ANTI-PATTERNS

| Forbidden | Why |
|-----------|-----|
| Create role without `.nix` file | Eval fails, role must exist in `modules/profiles/` |
| Use `with pkgs;` | Breaks static analysis, use explicit `pkgs.<name>` |
| Hardcode secrets | Use `sops.secrets` with proper `sopsFile` paths |
| Skip `lib.mkIf cfg.enable` | Config applies unconditionally |
| Assume `hostConfig.roles` exists | Pass as argument or check `config` availability |

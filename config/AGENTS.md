# config/

## OVERVIEW

Central configuration hub for cluster topology, node definitions, service IPs, and user accounts.

## STRUCTURE

| File | Purpose |
|------|---------|
| `default.nix` | Root config aggregator; exports `homelab.*` namespace with paths, domain, timezone |
| `nodes.nix` | Host definitions (5 nodes), role assignments, auto-generated groups |
| `kubernetes.nix` | K8s VIP, LoadBalancer IPs (10.10.10.100-199), database list, namespaces |
| `users.nix` | Admin user, SSH keys |

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new node | `nodes.nix` | Add entry to `hosts` attrset with roles, IP, machine type |
| Change node roles | `nodes.nix` | Edit `roles` list; must match filename in `modules/profiles/` |
| Reserve LoadBalancer IP | `kubernetes.nix` | Add entry to `loadBalancer.services` |
| Add database | `kubernetes.nix` | Append to `databases.postgres` list |
| Change cluster domain | `default.nix` | Edit `domain` field |
| Add SSH key | `users.nix` | Append to `admin.keys` |

## CONVENTIONS

### Node Naming
- Format: `lab-{greek}-{suffix}` (e.g., `lab-alpha-cp`, `lab-gamma-wk`)
- Suffixes: `-cp` (control-plane), `-wk` (worker), `-bk` (backup)

### Role System
- Roles auto-enable profiles from `modules/profiles/<role>.nix`
- Groups auto-generated via `filterByRoles` function
- Valid groups listed in `nodes.nix` `groups` attribute

### IP Allocation
- `10.10.10.200-203`: Node IPs
- `10.10.10.250`: K8s VIP (HAProxy)
- `10.10.10.100-199`: LoadBalancer services

## ANTI-PATTERNS

| Forbidden | Why |
|-----------|-----|
| Hardcode paths outside `paths` attrset | Use `config.homelab.paths.*` for portability |
| Add roles without creating profile file | Role must exist in `modules/profiles/` or eval fails |
| Duplicate LoadBalancer IPs | Cilium will fail to allocate |
| Use string IPs elsewhere | Reference `kubernetes.nix` attrs for consistency |

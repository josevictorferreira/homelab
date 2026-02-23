# HOSTS KNOWLEDGE BASE

> **Before starting any host configuration, read `.docs/rules.md` for project-specific lessons and gotchas.**

## OVERVIEW

Host entry point and hardware-specific configurations for NixOS machines.

## STRUCTURE

```
hosts/
├── default.nix              # Host entry point - imports hardware + profiles by role
├── hardware/                # Machine-specific hardware configs
│   ├── intel-nuc-gk3v.nix
│   ├── intel-nuc-t9plus.nix
│   ├── amd-ryzen-beelink-eqr5.nix
│   └── raspberry-pi-4b.nix
├── nix-base-install.nix     # Bootstrap installer for new nodes
└── nixos-recovery-iso.nix   # Rescue ISO with ZFS and recovery tools
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new machine type | `hardware/<machine>.nix` | Import `not-detected.nix`, set `hostPlatform` |
| Change node roles | `config/nodes.nix` | Roles auto-import profiles via `default.nix` |
| Bootstrap new node | `nix-base-install.nix` | Minimal installer with SSH, ZFS support |
| Recovery/rescue | `nixos-recovery-iso.nix` | Build ISO with `nix build .#nixosConfigurations.recovery.config.system.build.isoImage` |
| Fix Pi USB issues | `hardware/raspberry-pi-4b.nix` | UAS blacklist + quirks for SanDisk SSDs |

## CONVENTIONS

- **Hardware files**: Named by machine type, not hostname
- **ZFS root**: Use `rpool/{root,nix,log}` dataset structure
- **Host ID**: Generate from hostname hash: `builtins.substring 0 8 (builtins.hashString "sha1" hostname)`
- **Profiles**: Auto-imported from `modules/profiles/` based on `hostConfig.roles`

## ANTI-PATTERNS

| Forbidden | Why |
|-----------|-----|
| Edit `hardware-configuration.nix` directly | Use `hardware/` modules imported by `default.nix` |
| Hardcode host-specific values in hardware modules | Hardware configs are shared across nodes |
| Skip `hostPlatform` declaration | Required for proper architecture detection |
| Use GRUB on Pi | Use `generic-extlinux-compatible` for ARM |

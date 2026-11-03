---
name: "nixos-homelab-deployment"
description: "Deploy, validate, and troubleshoot NixOS host configurations and k3s node roles across the homelab cluster. Use when running make deploy/gdeploy/check, updating hosts/ or modules/profiles/, modifying node roles in config/nodes.nix, or debugging host networking."
---

# NixOS Homelab Deployment

Use this skill when modifying, validating, or deploying NixOS system configurations across cluster nodes (`lab-alpha-cp`, `lab-beta-cp`, `lab-gamma-wk`, `lab-delta-cp`, `lab-pi-bk`).

## Host Deployment Workflow

- **Validate**: `make check` (runs formatting, deadnix, statix, and `nix flake check`).
- **Interactive Deploy**: `make deploy` (fzf host selector; runs `nixos-rebuild switch --target-host`).
- **Role Group Deploy**: `make gdeploy` (deploys by role: `k8s-control-plane`, `k8s-worker`, etc.).
- **Dry Run**: `make ddeploy` (dry activation test before real deploy).

---

## Gotchas & Rules

### 1. Pi (`lab-pi-bk`, aarch64) Deployments Must Build Natively on the Pi
- **Rule**: Never run `nixos-rebuild --target-host` from an x86_64 workstation targeting `lab-pi-bk`. SSH to the Pi (`ssh root@10.10.10.209`) and rebuild locally.
- **Why**: x86_64 workstations cannot cross-compile aarch64 NixOS configurations without remote builders.
- **Crucial Gotcha for Uncommitted Changes**: When rebuilding on the Pi, running `nixos-rebuild switch --flake github:josevictorferreira/homelab#lab-pi-bk` evaluates the committed remote HEAD on GitHub and **silently ignores all local working tree edits**. To deploy uncommitted changes, copy the local flake directory to the Pi and build from that local path.
- **Verify**: `ssh root@10.10.10.209 'journalctl -u k3s | tail -20'` verifies newly applied units.

### 2. Keep `accept_local = 1` to Prevent Tailscale Dropping Cilium Ingress
- **Rule**: Ensure `boot.kernel.sysctl."net.ipv4.conf.all.accept_local" = 1;` remains enabled in `modules/profiles/k8s-server.nix`.
- **Why**: Tailscale 1.98+ forces `net.ipv4.conf.all.src_valid_mark = 1`. The Linux reverse-path filter reuses Cilium's proxy mark (`0x200`), routes through routing table 2004 (where all cluster IPs are local), and drops all ingress traffic from the LAN to `*.josevictor.me` services as martian packets.
- **Verify**: `ssh root@<node> 'ip route get 10.10.10.110 from 10.10.10.10 iif enp1s0 mark 0x200'` returns a valid `local` route instead of `Invalid argument`.

### 3. Assign Separate Load-Balancer Port (`6446`) to the etcd-only Pi
- **Rule**: The etcd-only Pi must pass `--lb-server-port=6446` in `etcdOnlyFlags` (`modules/profiles/k8s-server.nix`).
- **Why**: The Pi runs etcd-only and listens on `--https-listen-port=6444`. In k3s, 6444 is also the default `--lb-server-port`. Without `--lb-server-port=6446`, k3s's internal client load balancer points at its own supervisor, looping into itself and hanging indefinitely before etcd starts.
- **Verify**: `ssh root@10.10.10.209 'journalctl -u k3s | grep "Running load balancer"'` shows `127.0.0.1:6446 ... [default: 127.0.0.1:6444]`.

### 4. Bootstrap Resources Require NixOS Redeployment to Init Node (`lab-beta-cp`)
- **Rule**: Do not attempt to modify bootstrap resources (ResourceQuota, LimitRange) via `kubectl`. Update the NixOS module and redeploy `lab-beta-cp`.
- **Why**: K3s's built-in `objectset.rio.cattle.io` addon controller automatically reconciles bootstrap manifests from `/var/lib/rancher/k3s/server/manifests/` on the init control-plane node (`lab-beta-cp`). Any manual `kubectl patch` or `apply` is immediately overwritten and reverted.
- **Verify**: Inspect manifest on init node: `ssh root@lab-beta-cp 'cat /var/lib/rancher/k3s/server/manifests/resource-quotas.yaml'`.

### 5. Profile Filenames Auto-Discover Roles & Check Common Secrets First
- **Rule**: Roles in `config/nodes.nix` are auto-discovered from filenames in `modules/profiles/*.nix`. Adding a role requires creating the `.nix` file. Check `modules/common/sops.nix` before declaring host secrets in profiles.
- **Why**: Adding an unknown role string in `config/nodes.nix` fails Nix evaluation if no matching profile exists. Declaring secrets in profiles that already exist in `modules/common/sops.nix` (e.g. `tailscale_auth_key`) fails evaluation with duplicate definition errors.
- **Verify**: `make check` passes without role lookup or duplicate option definition errors.

### 6. Declare Transitive Binary Dependencies in Systemd Unit `path`
- **Rule**: Always explicitly declare all CLI utilities called by custom scripts in `systemd.services.<name>.path = [ pkgs.x pkgs.y ];`.
- **Why**: NixOS systemd services run in an isolated environment with a stripped `PATH`. Indirect binary calls (e.g. MinIO Client `mc` invoking `getent` internally to resolve the home directory) fail with "command not found" unless `pkgs.getent` is in `path`.
- **Verify**: `journalctl -u <service> --no-pager | grep -iE 'not found|error'` is clean after deployment.

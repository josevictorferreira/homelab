# Implementation Plan: Platform upgrade (NixOS 26.05, k3s 1.36, Cilium 1.20, Rook 1.21/Tentacle, Flux 2.10)

**Feature:** 0004-platform-upgrade-2026-11
**Date:** 2026-10-29
**Status:** executed 2026-10-29/30. All phases are done except the two items listed under "Not done" below.

## Outcome (2026-10-30)

| Component | Result |
|---|---|
| Rook / Ceph | 1.21.1 / Tentacle 20.2.4; daemon cephx keys rotated to aes256k; cephcsi held at 3.17.1, because 3.18 needs x86-64-v3 and the N5105 nodes lack it |
| NixOS | 26.05 on alpha, beta, gamma, delta and the Pi (kernel 6.18) |
| k3s | 1.32.7 → 1.33.3 → 1.34.11 → 1.35.8 → 1.36.4, pinned as `pkgs.k3s_1_36` |
| Cilium | 1.18.7 → 1.19.10 → 1.20.4, `upgradeCompatibility = "1.18"`, `bpf.datapathMode = "veth"` |
| Flux | 2.6 → 2.10.0; `.k8s/flux-system` is now tracked in git |
| Charts | cert-manager 1.21.3, CNPG 0.29.1, Alloy 1.14.4, kube-prometheus-stack 92.16.1, Loki 20.2.0, Velero 12.2.2 (plugin 1.14.4), app-template 5.3.0, plus home-assistant, n8n, open-webui, searxng, immich, keycloak, sftpgo and redis at their latest charts |

Fixes the upgrade turned up:

1. **Tailscale 1.98 sets `src_valid_mark=1`.** Under Cilium's TPROXY routing this dropped every LAN request to the ingress, and under Cilium 1.20 it also dropped Envoy's connections to pods on its own node. Fixed with `net.ipv4.conf.all.accept_local = 1` in `modules/profiles/k8s-server.nix`.
2. **The etcd-only Pi deadlocked on k3s 1.34.** Its client load balancer and the supervisor share port 6444. Fixed with `--lb-server-port=6446`, plus a one-time rewrite of the Pi's `server/cred/*.kubeconfig` files to `:6446`.
3. **k3s 1.33 in nixpkgs 26.05 is EOL and uncached.** The cached 1.33.3 from the old 25.05 rev was used for that one step.
4. **Chart-specific fixes:**
   - Cilium 1.19 sets a bare-integer CPU limit; it is overridden with a string.
   - searxng 1.3 adds a volume that collided with ours by name; ours was renamed.
   - The immich chart's remote JSON schemas are stripped before rendering.
   - Velero's immutable CRD-upgrade Job had to be deleted before reconciling.

Not done:

- **Rook `requireMsgr2 = true`.** The workstation's `~/Homelab` CephFS kernel mount (configured in `~/.config/nix`, outside this repo) uses the v1 monitor port 6789. It must move to msgr2 (port 3300, `ms_mode=prefer-crc`) first.
- **lab-oci-bk is still on 25.05.** Its disk is 99% full with the MinIO offsite mirror, and that data was not touched.

Follow-ups:

- **Pi SD card.** The 2020 SL16G card averages ~600 ms per write. It slows every rollout and stalls etcd during server restarts. Replace it or move the root to a USB SSD.
- **Pi etcd snapshot offload.** The offload service only uploads `*.db` files, but k3s snapshots have no extension, so nothing has ever been uploaded.
- **Two managers for `cilium.yaml`.** Flux and beta's k3s addon controller both apply it, so every Cilium bump rolls the DaemonSet twice.
- **CSI cephx keys stay `aes`.** Kernels below 7.0 can't use aes256k, so Ceph keeps warning about insecure key types and emergency ciphers.
- **Pre-existing issues:**
  - MinIO is marked insecure in nixpkgs.
  - The `apps/wildcard-tls` Certificate has been failing since 2026-08-17.
  - The CNPG `app` role is missing.

## 0. Non-negotiables

1. **One minor at a time where upstream says so.** k3s (Kubernetes skew policy), Cilium, cert-manager. No skipping.
2. **Every phase has a gate** (pass/fail commands). Nothing starts until the previous gate is green.
3. **Ceph is never touched while `ceph health` is `HEALTH_ERR`** and never with PGs not `active+clean`. `continueUpgradeAfterChecksEvenIfNotHealthy` stays `false`.
4. **Repo rules.** Cluster changes go Nix → `make manifests` → commit (with approval) → Flux. NixOS changes go build → `nix copy` → `switch-to-configuration` (deploy-rs is broken, see memory). The only direct `kubectl` actions are read-only checks, the one-time `flux` self-upgrade apply, and `kubectl delete pod` for rolling daemons that Rook/Helm will not roll themselves.
5. **Node order.** Workers before control plane for OS changes (gamma → alpha → delta → beta → pi). Servers before agents for k3s minors (beta → delta → pi, then alpha → gamma). Move the etcd leader to delta before touching beta (memory: etcd-leader-move-k3s).
6. **Rollback stays possible** until the explicit one-way steps: Ceph Tentacle (`require_osd_release`) and the ZFS pools (never `zpool upgrade`).

---

## 1. Inventory: current → target

| Component | Now | Target | Notes |
|---|---|---|---|
| NixOS | 25.05 (EOL 2025-12-31), kernel 6.12.63, zfs 2.3 | **26.05 "Yarara"** (kernel 6.18.59, zfs 2.4.4, nix 2.34) | 26.11 ships 2026-11-23; adopt it in Dec/Jan after 2–3 patch weeks. 26.05 is required anyway: it is the last release that still ships `k3s_1_33`. |
| k3s | v1.32.7+k3s1 (nixpkgs 25.05 `pkgs.k3s`) | **v1.36.4+k3s1** via 1.33.13 → 1.34.11 → 1.35.8 → 1.36.4 (all in nixpkgs 26.05) | `pkgs.k3s` in 26.05 is **1.35.8**: the OS upgrade MUST pin `services.k3s.package` explicitly or it silently jumps two minors. k3s 1.37 is not in 26.05. |
| Cilium | 1.18.7 | **1.20.4** via 1.19.10 | 1.18 tested k8s ≤1.33; 1.19: 1.32–1.35; 1.20: 1.33–1.36. Interleave with k3s steps. |
| Rook | 1.20.7 | **1.21.1** (+ ceph-csi-drivers 1.0.4 → 1.1.0) | needs k8s ≥1.32 ✓. msgr2 required by default in 1.21 (we set `requireMsgr2=false`; kernel ≥5.11 so can flip later). |
| Ceph | 19.2.4 Squid | **19.2.7** (last Squid, EOL **2026-10-31**) then **20.2.4 Tentacle** (EOL 2027-06) | Tentacle is one-way. Umbrella 21.2.0 is 1 day old: skip. |
| Flux | 2.6.x (helm-ctl 1.3.0, kustomize-ctl 1.6.0; EOL 2026-06-30) | **2.10.0** | Direct v2.x → v2.x jump is supported. `gotk-components.yaml` is **not in git anymore** (only in-cluster); restore it. 2.10 lists k8s 1.35–1.37 → do after k3s 1.35. |
| cert-manager | 1.18.2 | **1.21.3** via 1.19 → 1.20 → 1.21 | CRDs via chart `crds.enabled`. |
| kube-prometheus-stack | 77.11.1 | **92.16.0** | 15 chart majors; read each major's upgrade note (CRDs via `includeCRDs`, Grafana major). |
| Loki chart | 18.13.7 (repo moved to grafana-community) | **20.0.3** (Loki 3.7.9) | two chart majors, values changes. |
| Alloy chart | 1.13.0 | 1.14.4 | low risk. |
| Velero chart | 11.3.2 | **12.2.1** (Velero 1.18.2) | `includeCRDs = false` → Velero CRDs are not managed by the chart render; update them explicitly. |
| CloudNativePG | chart 0.29.0 (op 1.30.0) / barman plugin 0.8.0 | 0.29.1 (1.30.1) / 0.8.1 | patch; in-tree barman removal is 1.31 (Dec 2026), we already use the plugin. |
| bjw-s app-template | 4.2.0 | **5.3.0** | chart major → values schema change for every app using `_submodules/release.nix`. Own phase. |
| amd-gpu device plugin | 0.20.0 | 0.22.0 | low risk. |
| App charts | home-assistant 0.3.68, n8n 1.15.5, open-webui 8.1.0, searxng 1.1.0, immich 0.10.3, keycloak 0.14.2, sftpgo 0.47.0, redis 22.0.7, imgproxy 1.1.0 | latest per app | last, one app per commit. |
| Flake inputs | sops-nix, disko, kubenix, terranix, deploy-rs, nix-openclaw | `nix flake update` per input | deploy-rs may start working again; re-test. |

Verified facts behind the table: `nix eval` of nixpkgs 26.05/25.11 for `k3s_1_3x`, Helm `index.yaml` of every repo (2026-10-29), Cilium per-version compatibility pages, Rook 1.21 upgrade guide, Ceph releases index, Flux endoflife + 2.10 notes, NixOS 25.11/26.05 release notes.

---

## 2. Ordering and why

```
P0 prep ─► P1 Ceph/Rook (Squid EOL in 2 days) ─► P2 independent charts
        ─► P3 NixOS 26.05 (k3s pinned at 1.32) ─► P4 k3s 1.33 ─► Cilium 1.19
        ─► k3s 1.34 ─► k3s 1.35 ─► Cilium 1.20 ─► k3s 1.36
        ─► P5 Flux 2.10 ─► P6 monitoring/backup/app-template majors ─► P7 apps ─► P8 cleanup, 26.11 later
```

- Ceph first because Squid is EOL on 2026-10-31 and Rook 1.21 only needs k8s ≥1.32, which we already have.
- NixOS before k3s because 25.05 has no k3s 1.33 package; 26.05 has 1.33–1.36.
- Cilium 1.19 sits between k3s 1.33 and 1.34 (1.18 is not tested past 1.33); Cilium 1.20 before k3s 1.36 (1.19 is not tested past 1.35).
- Flux after k3s 1.35 (its support window), but the 2.6 → 2.10 jump itself is supported.

---

## 3. Phases

### P0. Preparation (no cluster change)

1. Disk headroom: Pi SD root is 85 % (2.2 G free) and beta rpool 77 %. `nix-collect-garbage --delete-older-than 14d` on every host; confirm ≥5 G free on the Pi before any aarch64 switch.
2. Fresh backups: etcd snapshot on beta (`k3s etcd-snapshot save`), CNPG `Backup` CR completed, Velero backup of `apps`/`databases`, `zfs snapshot rpool@pre-upgrade` on beta/delta.
3. Clear what is stale: `ceph osd unset noout/noscrub/nodeep-scrub` once the cluster has been quiet for a day (scrub backlog is 394 PGs). Keep `noout` back on only while rolling OSDs.
4. Fix tooling: `make deploy`/deploy-rs is broken (memory). Either retest after the flake update in P3 or add a `make deploy-host HOST=` target around the build + `nix copy` + `switch-to-configuration` recipe. The Pi builds on `lab-oci-bk` (memory: OCI-box-is-Pi-builder).
5. Grep the NixOS config for options removed in 25.11/26.05. Known hits: `hardware.amdgpu.amdvlk` in `modules/profiles/amd-gpu.nix` (removed in 25.11, RADV is default → delete the block). Review: `boot.initrd.systemd` default flip (ZFS root on beta/delta/eqr5 hardware), `network-setup.service` folded into `network.target` (our storage-network comment references it), `services.openssh.settings.AcceptEnv` must be a list, dbus-broker default.
6. Gate: all nodes Ready, `ceph health` ≠ ERR, 394 PGs active+clean, Pi ≥5 G free, backups listed above exist.

### P1. Rook 1.21.1 + Ceph 19.2.7 → 20.2.4

1. `rook-ceph-operator.nix` 1.20.7 → 1.21.1, `ceph-csi-drivers.nix` 1.0.4 → 1.1.0, `rook-ceph-cluster.nix` chart 1.20.7 → 1.21.1. Helm order is operator → csi-drivers → cluster; with Flux all three land in one reconcile, so commit them together and watch the operator log for the CSI migration. The guide says delete StorageClass `ceph-block` before the upgrade if its immutable `parameters` change; check our StorageClass names (`rook-ceph-block`, `rook-ceph-block-nvme`) against the 1.21 chart diff first.
2. Keep `network.connections.requireMsgr2 = false` for this step. Flip it to `true` in P8 (kernel 6.18, all nodes ≥5.11); existing mounts keep msgr1 until remounted.
3. Gate: operator `Ready`, all OSD/mon/mds/csi pods on the 1.21.1 images, HEALTH_OK/WARN-only, 394 active+clean, a PVC create+mount smoke test.
4. `cephVersion.image` 19.2.4 → **19.2.7** (same tag format with build date). Rook rolls daemons one by one. Gate: `ceph versions` shows one version, PGs clean.
5. Disable the `rook` mgr module in `spec.mgr.modules` (Rook recommends before Tentacle), then `cephVersion.image` → **20.2.4-20260818**, and bump the toolbox image to match. **One-way.** Gate: `ceph versions` all 20.2.4, `ceph osd dump | grep require_osd_release` = tentacle, HEALTH_OK/WARN-only, RBD + CephFS mounts on every node still serving, Hermes/openclaw CephFS workloads fine.
6. Watch for: `too many PGs per OSD (295 > 250)` is a WARN now; check whether Tentacle hardens `mon_max_pg_per_osd` (raise it or reduce PG counts beforehand). The 19.2.3 BlueFS truncate assert (memory) does not apply to 19.2.7/20.2.4.

### P2. Independent chart patches (current k8s)

Each its own commit + Flux reconcile + gate (pods Running, no CRD errors in Flux):
1. CNPG 0.29.0 → 0.29.1, plugin-barman-cloud 0.8.0 → 0.8.1 (operator restart only; verify a WAL archive and `Backup`).
2. cert-manager 1.18.2 → 1.19.x → 1.20.x → 1.21.3, one minor per commit (wildcard cert must stay valid; `cmctl check api`).
3. alloy 1.13.0 → 1.14.4, amd-gpu 0.20.0 → 0.22.0.

### P3. NixOS 25.05 → 26.05 with k3s held at 1.32

1. `flake.nix`: `nixpkgs` → `nixos-26.05`; add input `nixpkgs-2505` (current lock) and set `services.k3s.package = nixpkgs-2505.legacyPackages.${system}.k3s` (1.32.7) so the OS upgrade changes nothing in k3s. Update the other inputs (`nix flake update`), fix `amdvlk`, `nix flake check`.
2. Build all five toplevels first (x86 locally, Pi on lab-oci-bk). Diff `switch-to-configuration dry-activate` per host; expect kernel + systemd + stage-1 changes → a reboot per host.
3. Order and per-node gate: **gamma** (worker, OSD 3) → alpha (worker, OSDs 1/2, mon-a) → delta (CP, OSD 0, mon-b) → beta (CP, VIP, OSD 4, mon-c; move etcd leader to delta first) → pi (etcd-only). After each reboot: node Ready, `storage0` back at 2.5 G (the udev rename is now in the link file, no manual trigger expected), its OSD up on 10.10.20.x, PGs active+clean, etcd 3/3, AC-restore/WoL still works.
4. systemd stage-1 risk: ZFS-root hosts (beta t9plus, delta eqr5). Do gamma first; if stage-1 misbehaves anywhere, set `boot.initrd.systemd.enable = false` for that host for this release only (removed in 26.11).
5. Gate: all five on NixOS 26.05 / kernel 6.18, k3s still v1.32.7, Ceph clean, `zpool status` healthy and **not upgraded**.

### P4. k3s minors interleaved with Cilium

For every k3s step: change `services.k3s.package` (`k3s_1_33` → `k3s_1_34` → `k3s_1_35` → `k3s_1_36`), rebuild, switch **beta → delta → pi** (servers, one at a time, each must rejoin etcd and report Ready at the new version before the next), then **alpha → gamma**. Read the Kubernetes "urgent upgrade notes" for that minor and the k3s release page. Known k3s items: 1.34 drops the `master` role label/taint (grep manifests for `node-role.kubernetes.io/master`), switches to EndpointSlices; 1.35/1.36 have no listed breaking flags; Traefik is disabled here so its chart changes do not matter. Gate per step: `kubectl get nodes` all at the new version, etcd healthy, Flux Ready, Ceph clean, no CrashLoop in `apps`.

Cilium steps (kubenix `system/cilium.nix`):
1. **1.19.10** after k3s 1.33: run the pre-flight DaemonSet (`preflight.enabled=true`) and wait for READY = cilium pods; set `upgradeCompatibility` to `1.18`; remove any `FromRequires/ToRequires`; migrate `_crds.nix` entries at `cilium.io/v2alpha1` (`CiliumLoadBalancerIPPool`, L2 policy) to `v2`; check our values for removed flags (`enable-node-port/host-port/external-ips` → `kubeProxyReplacement=true`, `l2-pod-announcements-interface` → pattern). Our L2 interface pin `^enp1s0$` stays (keep `storage0` out of L2, memory: cilium-l2-tailscale-arp-crash).
2. **1.20.4** after k3s 1.35: pre-flight again; `CiliumNodeConfig` v2alpha1 → v2; no kafka/L7 rules exist (verify); Gateway API only if we install those CRDs (we use Cilium ingress, verify); **pin `bpf.datapathMode = veth`**: 1.20 defaults to `auto` which picks netkit on 6.18 and is incompatible with `bpf.tproxy=true` (the TPROXY ingress path the Pi firewall note depends on). Gate: `cilium status` all OK, ingress + LB IPs + L2 ARP for 10.10.10.100-199 answer from every VLAN client, Hubble not required.

### P5. Flux 2.6 → 2.10

1. Generate with the 2.10 CLI (`nix run github:NixOS/nixpkgs/nixpkgs-unstable#fluxcd -- install --export`, nixpkgs 26.05 ships 2.9.5) into `.k8s/flux-system/gotk-components.yaml`, re-add the directory to git (the manifest pipeline already preserves `flux-system/`). Keep `gotk-sync.yaml` from the cluster (`kubectl get gitrepository,kustomization -n flux-system -o yaml`).
2. One-time `kubectl apply --server-side --force-conflicts -f .k8s/flux-system/gotk-components.yaml` (Flux cannot upgrade its own CRDs through itself), then `flux reconcile ks flux-system --with-source`.
3. `flux migrate` for `notification.toolkit.fluxcd.io/v1beta3` (Alert/Provider) if any exist; note the RBAC change for `serviceaccounts/token` (only if object identity is used: not here).
4. Gate: `flux check`, all Kustomizations Ready, controllers on 2.10 images.

### P6. Monitoring, backup, app-template majors

1. kube-prometheus-stack 77 → 92: step through the chart majors' upgrade notes (CRD bumps are rendered via `includeCRDs`, so each bump must be committed with its CRDs); Grafana major; Alertmanager config unchanged. Gate: Prometheus targets up, Grafana login (OIDC), dashboards load.
2. Loki 18 → 19 → 20 (grafana-community repo; values renames), Alloy already done. Gate: logs flowing (hermes/valoris error-triage depends on Loki).
3. Velero 11.3.2 → 12.2.1: update CRDs explicitly (chart render has `includeCRDs=false`), then chart; `velero backup create` smoke + BSL Available.
4. bjw-s app-template 4.2.0 → 5.3.0 in `_submodules/release.nix`: diff the 5.x values schema (controllers/containers/service/ingress/persistence keys), convert the submodule once, test on one app (e.g. searxng), then let Flux roll the rest; expect rollout restarts across `apps`.

### P7. Application charts

One app per commit, newest first where security matters: home-assistant 0.3.89, n8n 1.24.x (n8n 2.x major), open-webui (chart 17.x, check it is not a dev tag), searxng 1.3.1, immich, keycloak, sftpgo, redis, imgproxy. Pinned images with digests stay the rule.

### P8. Cleanup and follow-ups

1. Remove the `nixpkgs-2505` input and the explicit k3s pin (or keep the pin as `pkgs.k3s_1_36` to avoid surprise bumps on later channel updates: recommended).
2. Rook `requireMsgr2 = true`; remount-sensitive pods get restarted over time.
3. Clear `noout/noscrub/nodeep-scrub`; let scrubs catch up.
4. Update CLAUDE.md "NODES"/versions, memories: deploy recipe, Flux location, k3s pin rule.
5. NixOS 26.11 in Dec 2026/Jan 2027 (drops scripted stage-1 and `k3s_1_33`; irrelevant by then). Ceph Umbrella 21.x only after 21.2.1+.

---

## 4. Risks worth saying out loud

- **Pi SD card space and speed.** Every NixOS/k3s switch on the Pi copies a closure to a 15 G card at 85 %. Garbage-collect first; expect 10–20 min per switch; it is etcd-only so the cluster keeps quorum with beta+delta meanwhile.
- **Storage cascade.** A storage node reboot while another is unhealthy stalls RBD and starves etcd (memory: storage-node-down-cascades-controlplane-outage, and today's outage). Never have two of alpha/beta/delta down at once; always gate on PGs active+clean.
- **Silent k3s double-jump.** `pkgs.k3s` in 26.05 is 1.35. Without the explicit pin the OS upgrade would move 1.32 → 1.35 in one reboot.
- **Cilium netkit default** in 1.20 vs our TPROXY ingress. Pin veth.
- **Flux self-upgrade** needs one direct apply; everything else stays GitOps.
- **Tentacle is irreversible**; Squid EOL forces it anyway.
- **app-template 5.x** touches every app at once through the shared submodule; do it in a quiet window.

## 5. Effort estimate

| Phase | Hands-on | Calendar |
|---|---|---|
| P0 | 1 h | same day |
| P1 Rook+Ceph | 2–3 h (Rook) + 2 h (two Ceph rolls) | 2 evenings |
| P2 | 1 h | 1 evening |
| P3 NixOS | 1 h build + ~20 min per node | 1 evening (Pi may spill) |
| P4 k3s×4 + Cilium×2 | ~45 min per k3s step, ~45 min per Cilium | 2–3 evenings |
| P5 Flux | 45 min | 1 evening (with P6.1) |
| P6 | 3–4 h | 2 evenings |
| P7 | per app | ongoing |

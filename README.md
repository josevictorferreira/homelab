# Homelab Nix Configs

My Homelab to self-host some services and tools that I use everyday. Besides from the utility that the services provide, this project is also used as a way to learn new cool tech, like Networks, Kubernetes, Devops, HA, Cloud Provisioning and so on. The challenge is to have High Availability using only cheap devices, that was mostly underused or accumulating some dust on my basement. Power efficiency is also a "must", since I don't wan't this to turn into a expensive hobby.


## Machines

| Node | Processor | Cores | Socket | Frequency Range | Memory | Storage | Address |
|----------------|---------------------------------------------------------------------------|-------|-----------|------------------------|------------|---------------------------------------------------|---------------|
| lab-alpha-cp | Intel(R) Celeron(R) N5105 | 4 | 1 socket | 800MHz to 2900MHz | 15Gi total | 260GB NVMe + 1TB SSD | 10.10.10.200 |
| lab-beta-cp | Intel(R) N100 | 4 | 1 socket | 700MHz to 3400MHz | 15Gi total | 500GB NVMe | 10.10.10.201 |
| lab-gamma-wk | Intel(R) Celeron(R) N5105 | 4 | 1 socket | 800MHz to 2900MHz | 7.6Gi total| 260GB NVMe + 256GB HD | 10.10.10.202 |
| lab-delta-cp | AMD Ryzen 5 PRO 5650U with Radeon Graphics | 6 | 1 socket | 400MHz to 4289MHz | 11Gi total | 500GB NVMe | 10.10.10.203 |
| lab-pi-bk | ARM Cortex-A72 | 4 | no socket | 600MHz to 1500MHz | 3.7Gi total| 16GB Micro SD + 1TB USB external SSD | 10.10.10.209 |



## Cluster

Cluster k3s on each node, with `traeffik`and `servicelb` disabled. Name definition: `{three letter indicating the zone/location of the cluster}-{alphabet in order of machine age in cluster}-{two letters indicating the machine role in the cluster}`.

Locations:
1. lab (Currently the only cluster)

Roles:
1. cp (Kubernetes control planes nodes)
2. wk (Kubernetes worker/agent nodes)
3. bk (Backup machines, used only for backup routines outside the cluster)


| Machine | Hostname | OS | Role | Notes |
| ------------- | -------------- | ----- | ----------------------- | -------------------------------------------------------------------- |
| lab-alpha-cp | lab-alpha-cp | NixOS | k3s server (`--init`) | Don't use NoSchedule taint |
| lab-beta-cp | lab-beta-cp | NixOS | k3s server | |
| lab-gamma-wk | lab-gamma-wk | NixOS | k3s agent | |
| lab-delta-cp | lab-delta-cp | NixOS | Control-plane | |
| lab-pi-bk | lab-pi-bk | NixOS | Backup & utility server | - NFS share or MinioIO<br>- Node status check & WOL<br>- Backup jobs |



## Network

On the kubernetes cluster, we'll use `Cilium` instead of `Flannel`.


## Storage

Tools to be used:

| Need | Tool | Notes | 
| ------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| K8s Storage Classess with RWM support | Rook-Ceph | Will need to add storage drives just for Ceph usage. |
| POSIX Filesystem for file sharing | Rook-Ceph | CephFS csi avilable. |
| Network file sharing | A NFS and SMB share that uses CephFS Storage Class | Must assign a password on both for access in the network. |
| Node Filesystem Recovery | ZFS in all filesystems | On the main nodes use it with a Mirror partition. On the external drive use it Single only. |


Disk layout per node:

|Mount|Size guideline|ZFS dataset|Why|
|---|---|---|---|
|`/`|20 GiB on **mirror** of first NVMe (or single partition on Raspberry Pi)|`rpool/root` (`compression=zstd`)|immutable NixOS rollbacks|
|`/nix`|10 GiB|`rpool/nix`|keeps store snapshots small|
|`/var/log`|5 GiB, separate dataset|`rpool/log`|prevents runaway logs|
|**Ceph OSD(s)**|_rest of each drive_ as raw block, **not** inside ZFS|—|RBD wants direct disks, no double CoW|
|External USB SSD (Pi)|full drive, single ZFS pool|`backuppool`|off-cluster backups / MinIO|



## Secrets

Plain sops-nix to manage secrets across the project.
The project will have a file on the root called `.sops.yaml`and a folder with `secrets/*.enc.yaml` files.
The same folder will maintain secrets from the nixos nodes itself, but also the k8s.


## Observability

| Need | Tool | Notes | 
| -------------------------------------------------- | ---------- | -------------------------------------------------------------- |
| Collect metrics inside and outside the k8s cluster | Prometheus | Use the default `kube-prometheus-stack` helm chart |
| Metrics graphics and queries | Grafana | Installed using the same stack as prometheus |
| Logs collection and queries | Loki | OPTIONAL: In the first release I'll not worry about it for now |
| Old metrics magement | Thanos | OPTIONAL: Don't worry on the first release, it'll be disabled. |



## Backups / Recovery

| Need | Tool | Notes |
| --------------------- | ---------------------------- | ----------------------------------------------------------------------- |
| Cluster-aware backups | Velero with CSI | Supports Ceph snapshots natively |
| Dashboards | Ceph-Rook nativaly dashboard | Dashboards come builtin |
| Out-of-band Backups | MinIO | Installed on the backup-server and storing on the external USB storage. |



## Deployments & Cluster Management

For managing the nix configs and setup of the machines in each node, we'll use `rs-reploy`. To write manifests using the same language as the nodes config, we'll use `Kubenix`. Now for deploying the changes in the manifest and apply it on the k8s cluster, we'll use `Flux v2`.


## Applications Self-Hosted

This is the list of applications I have planned to install in the cluster:
- Postgresql
- Rabbitmq(especially for MQTT)
- Pihole
- Sftpgo
- Ntfy
- Uptime Kuma
- Qbittorrent + Gluetun
- Prowlarr
- AlarmServer (a custom ruby on rails application I've made to receive alerts from my CCTV cameras and forward to Ntfy + MQTT)
- Libebooker (a custom ruby on rails application I've made to turn any website article into a epub and send to my devices for read it later)
- Glance (dashboard home-page with some infos about my cluster)
- Jellyfin (later, dont worry about it now)
- Firefly 3 -> Personal finance manager


## Repository Structure

**Everything – NixOS hosts, Kubenix source, rendered YAML, Flux bootstrap, CI – lives here.** Flux will read only the sub‑path you point it at (e.g. `kubernetes/clusters/home`)

```
bash
homelab/
├── .github/
│   └── workflows/
│       ├── build-kubenix.yml      # CI: render Kubenix & check diff
│       └── lint.yml               # optional: nix flake check, shellcheck, etc.
├── .sourceignore                  # stops Flux from fetching huge/irrelevant blobs
├── .gitignore                     # ignores result/, *.qcow2, etc.
├── .pre-commit-config.yaml        # hooks: nix fmt, sops validate, treefmt
├── LICENSE                        # MIT or Apache‑2.0
├── README.md                      # project overview & bootstrap notes
├── flake.nix                      # inputs: nixpkgs, kubenix, deploy-rs, cilium, ...
├── flake.lock                     # pinned versions
├── scripts/                       # helper scripts executed by humans/CI
│   ├── render-kubenix.sh          # builds Kubenix and copies manifests
│   └── update-lock.sh             # refreshes flake.lock safely
├── secrets/
│   ├── cluster.age.pub            # **public** Age key for SOPS
│   └── .sops.yaml                 # rules: yamls in kubernetes/** get encrypted
├── nix/
│   ├── hosts/
│   │   ├── default.nix
│   │   └── hardware
│   │       ├── amd-ryzen-beelink-eqr5.nix
│   │       ├── intel-nuc-gk3v.nix
│   │       ├── intel-nuc-t9plus.nix
│   │       └── raspberry-pi-4b.nix
│   ├── modules
│   │   ├── common
│   │   │   ├── locale.nix
│   │   │   ├── nix.nix
│   │   │   ├── sops.nix
│   │   │   ├── ssh.nix
│   │   │   ├── static-ip.nix
│   │   │   └── users.nix
│   │   ├── programs
│   │   │   ├── git.nix
│   │   │   ├── vim.nix
│   │   │   └── zsh.nix
│   │   ├── roles
│   │   │   ├── backup-target.nix
│   │   │   ├── k8s-control-plane.nix
│   │   │   ├── k8s-worker.nix
│   │   │   ├── nixos-server.nix
│   │   │   └── system-admin.nix
│   │   └── services
│   │       ├── minio.nix
│   │       └── wake-on-lan-observer.ni
│   └── deploy/
│       └── deploy-rs.toml         # inventory & ssh cfg
├── kubernetes/
│   ├── pkgs/                      # Kubenix library overlay (optional)
│   └── clusters/
│       └── homelab/
│           ├── kustomization.yaml # entrypoint consumed by Flux
│           └── manifests/         # ← rendered YAML lives *committed* here
│               ├── 00-namespaces.yaml
│               ├── 10-storage.yaml
│               ├── 20-network.yaml
│               ├── 30-observability.yaml
│               └── apps/
│                   ├── pihole.yaml
│                   ├── ntfy.yaml
│                   └── ...
└── flux-system/                   # created by `flux bootstrap`; keep committed
    ├── gotk-components.yaml
    ├── gotk-sync.yaml
    ├── kustomization.yaml         # points to ./kubernetes/clusters/home
    └── sources.yaml               # GitRepository definition (no secretRef)
```


**Folder notes**
- `**nix/hosts/**` follows new hostname scheme (`ctrl`, `work`, `back`, ¬ class + ordinal).
- `**kubenix**` **build output** committed to Git until it becomes noisy → switch to OCI artefact + `OCIRepository`.
- `**secrets/**` contains only public materials and SOPS config; private Age key mounted in‑cluster via Secret.
- `**flux-system/**` stays under version control so that a fresh cluster can self‑bootstrap from Git alone.

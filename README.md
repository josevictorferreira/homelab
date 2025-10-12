# Homelab Cluster

My Homelab to self-host services and tools using a hybrid NixOS/Kubernetes architecture. This project combines immutable infrastructure with GitOps deployment to achieve high availability using cost-efficient hardware while maintaining power efficiency.

## Cluster Architecture

### Overview
This is a hybrid NixOS/Kubernetes homelab cluster that combines immutable OS configurations with containerized workloads using NixOS for host management and k3s Kubernetes for application deployment.

### Infrastructure Nodes

| Node | IP | Hardware | CPU | Memory | Storage | Roles |
|------|----|----------|-----|--------|---------|-------|
| **lab-alpha-cp** | 10.10.10.200 | Intel NUC GK3V | Intel Celeron N5105 (4 cores) | 15Gi | NVMe + SATA Ceph OSDs | k8s-control-plane, k8s-storage, k8s-server, system-admin |
| **lab-beta-cp** | 10.10.10.201 | Intel NUC T9Plus | Intel N100 (4 cores) | 15Gi | NVMe Ceph OSD | k8s-control-plane, k8s-storage, k8s-server, system-admin |
| **lab-gamma-wk** | 10.10.10.202 | Intel NUC GK3V | Intel Celeron N5105 (4 cores) | 7.6Gi | NVMe + SATA Ceph OSDs | k8s-worker, k8s-storage, k8s-server, system-admin |
| **lab-delta-cp** | 10.10.10.203 | AMD Ryzen Beelink EQR5 | AMD Ryzen 5 PRO 5650U (6 cores) | 11Gi | NVMe Ceph OSD | k8s-control-plane, k8s-storage, k8s-server, system-admin, amd-gpu |

### Node Roles System

**k8s-control-plane** (3 nodes: alpha, beta, delta)
- Runs k3s in server mode with HA setup
- HAProxy + Keepalived VIP (10.10.10.250) for API server
- etcd cluster with automatic snapshots every 12 hours
- Cilium CNI instead of Flannel for advanced networking
- Bootstrap manifests for system components and Flux GitOps

**k8s-worker** (1 node: gamma)
- Runs k3s in agent mode
- Resource management with image GC and eviction policies
- Connects to control plane via VIP for high availability

**k8s-storage** (all 4 nodes)
- Ceph Rook-Ceph distributed storage with OSDs on dedicated disks
- CephFS for shared filesystems and SMB exports
- Kernel modules: ceph, rbd, nfs

**amd-gpu** (1 node: delta)
- ROCm stack for GPU acceleration workloads
- AMDVLK drivers and Vulkan support
- Suitable for AI/ML applications

### Kubernetes Stack

**Core Components:**
- k3s lightweight Kubernetes distribution
- Cilium CNI for advanced networking and network policies
- Flux v2 for GitOps continuous delivery
- Cert-manager for automatic certificate management

**Storage Architecture:**
- Rook-Ceph for distributed storage across all nodes
- CephFS for shared POSIX filesystem access
- SMB exports for Windows compatibility
- Direct disk access for Ceph OSDs (no ZFS overlay)

### Key Technologies

- **NixOS**: Immutable OS configuration with declarative management
- **deploy-rs**: Remote deployment with group-based operations
- **kubenix**: Nix DSL for authoring Kubernetes manifests
- **Flux v2**: GitOps continuous delivery from git repository
- **Ceph**: Distributed storage via Rook-Ceph operator
- **sops-nix**: Integrated secret management with age encryption

### Configuration Management

**NixOS Configuration Flow:**
1. Host definitions in `config/nodes.nix` with role assignments
2. Role-based profiles in `modules/profiles/`
3. Hardware-specific configurations in `hosts/hardware/`
4. Deployed via deploy-rs with group-based deployment (`make gdeploy`)

**Kubernetes Manifest Flow:**
1. Applications authored as Nix in `kubernetes/kubenix/`
2. Built to YAML manifests with `nix build .#gen-manifets --impure`
3. Secrets injected using vals from encrypted sources
4. Encrypted manifests committed as `.enc.yaml` files
5. Flux automatically syncs changes to cluster

### High Availability Features
- 3-node control plane with etcd quorum
- Floating VIP for API server access
- Distributed storage with data replication
- Automatic failover and recovery mechanisms

## Common Commands

### NixOS & Deployment
- `make check` - Validate flake configuration
- `make deploy` - Interactive host deployment with fzf selection
- `make gdeploy` - Deploy hosts by group (interactive selection)

### Secrets Management
- `make secrets` - Interactive secret editing with fzf selection
- Uses sops-nix for encrypted configuration

### Kubernetes Operations
- `make manifests` - Complete pipeline: generate, inject secrets, encrypt, lock
- `make kubesync` - Copy kubeconfig from control plane to local
- `make reconcile` - Reconcile flux system with git repository

### Applications
The cluster runs various self-hosted applications deployed via Kubenix:
- **Infrastructure**: PostgreSQL, RabbitMQ, Redis
- **Services**: N8N, Immich, Glance dashboard, Blocky DNS
- **Media**: qBittorrent with VPN, SearxNG, YouTube Transcriber
- **Development**: OpenWebUI, Docling, LibeBooker
- **Monitoring**: Prometheus + Grafana stack

## Repository Structure

```
├── config/                 # NixOS configuration files
├── hosts/                  # Host-specific configurations
│   └── hardware/          # Hardware-specific nix configs
├── modules/
│   └── profiles/          # Role-based node configurations
├── kubernetes/
│   ├── kubenix/          # Nix DSL for K8s manifests
│   └── manifests/        # Generated YAML manifests
├── secrets/               # Encrypted secrets (sops)
└── Makefile              # Common commands and workflows
```

## Development Workflow

1. Edit NixOS configs or kubenix modules
2. Run `make manifests` for complete manifest build
3. Deploy changes (`make deploy` or `make gdeploy`)
4. Flux automatically applies kubernetes changes to cluster

This architecture provides a robust, scalable homelab environment with immutable infrastructure, GitOps deployment, and enterprise-grade features including distributed storage and high availability.
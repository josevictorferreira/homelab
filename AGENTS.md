# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### NixOS & Deployment
- `make check` - Validate flake configuration
- `make deploy` - Interactive host deployment with fzf selection
- `make ddeploy` - Dry-run deployment (interactive selection)
- `make gdeploy` - Deploy hosts by group (interactive selection)
- `nix build .#gen-manifests --impure` - Generate Kubernetes manifests

### Secrets Management
- `make secrets` - Interactive secret editing with fzf selection
- Uses sops-nix for encrypted configuration

### Kubernetes Operations
- `make manifests` - Full pipeline: generate manifests, replace secrets, encrypt, lock
- `make gmanifests` - Generate k8s manifests from kubenix configurations
- `make vmanifests` - Replace secrets in manifests using vals
- `make emanifests` - Encrypt .enc.yaml manifests with sops
- `make umanifests` - Restore unchanged files using lockfile tracking

### Cluster Management
- `make kubesync` - Copy kubeconfig from control plane to local kubectl config
- `make reconcile` - Reconcile flux system with git repository
- `make events` - Watch flux events

### Recovery
- `make wusbiso` - Build recovery ISO and write to USB drive

## Architecture Overview

### Repository Structure
- **Hybrid NixOS/Kubernetes**: Single repo manages both NixOS host configurations and K8s manifests
- **Kubenix Integration**: Kubernetes manifests authored in Nix and rendered to YAML
- **Flux GitOps**: Flux v2 syncs `kubernetes/manifests/` to cluster

### Core Configuration Flow
1. **NixOS Configs** (`config/`, `hosts/`, `modules/`) - Define host configurations with roles
2. **Kubenix Modules** (`kubernetes/kubenix/`) - Write K8s resources in Nix DSL
3. **Manifest Generation** - Nix build renders kubenix to YAML manifests
4. **Secret Management** - vals injects secrets, sops encrypts `.enc.yaml` files
5. **Flux Sync** - Flux applies manifests to cluster

### Node Roles System
- **Profile-based**: Hosts get roles like `k8s-control-plane`, `k8s-worker`, etc.
- **Role Modules**: `modules/profiles/*.nix` implement each role's specific config
- **Group Deployment**: Roles map to node groups for batch deployment

### Key Technologies
- **NixOS**: Immutable OS configuration
- **deploy-rs**: Remote NixOS deployment system
- **kubenix**: Nix DSL for Kubernetes manifests
- **k3s**: Lightweight Kubernetes distribution
- **Flux v2**: GitOps continuous delivery
- **Ceph**: Distributed storage via Rook-Ceph
- **sops-nix**: Secret management integration

### Infrastructure Details
- **Control Plane**: HA setup with HAProxy + Keepalived VIP (10.10.10.250)
- **Storage**: Ceph Rook-Ceph with dedicated OSD disks
- **Networking**: Cilium CNI instead of standard Flannel
- **Hardware**: Mixed x86_64 and aarch64 nodes with specific roles

### Development Workflow
1. Edit NixOS configs or kubenix modules
2. Run `make manifests` for complete manifest build
3. Deploy changes (`make deploy` or `make gdeploy`)
4. Flux automatically applies kubernetes changes
# AGENTS.md

This file provides guidance to Agentic AI when working with code in this repository.

## Common Commands

### NixOS & Deployment
- `make check` - Validate flake configuration
- `make deploy` - Interactive host deployment with fzf selection
- `make ddeploy` - Dry-run deployment (interactive selection)
- `make gdeploy` - Deploy hosts by group (interactive selection)

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

### Containers
- `make docker-build` - Build container images locally
- `make docker-login` - Login to ghcr.io using GitHub token from environment
- `make docker-push` - Push the builded image to ghcr.io

### Recovery
- `make wusbiso` - Build recovery ISO and write to USB drive

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Kubernetes homelab configuration using Helmfile for deployment management. The cluster runs on K3s with custom Helm charts and third-party charts to manage infrastructure and self-hosted services.

## Development Commands

### Primary Commands (via Makefile)
- `make help` - Show all available commands
- `make sync` - Sync all helmfile releases
- `make syncd` - Sync helmfile with debug output
- `make apply REL=<release_name>` - Apply specific release
- `make applyd REL=<release_name>` - Apply specific release with debug
- `make list` - List all available releases
- `make secrets` - Edit encrypted secrets using SOPS
- `make logs REL=<pod_name>` - Show logs for specific pod
- `make monitor` - Open k9s monitoring dashboard

### Secret Management
- `make gen_secret` - Generate random base64 secret
- `make gen_erlang_cookie` - Generate Erlang cookie for RabbitMQ
- Secrets are encrypted with SOPS in `environments/homelab/secrets.enc.yaml`

### Monitoring & Debugging
- `make listen_prometheus` - Port-forward to Prometheus on port 9090
- `make monitor` - Launch k9s in self-hosted namespace
- `kubectl logs -n self-hosted -l "app.kubernetes.io/name=<service>" --tail=100` - View service logs

## Architecture

### Core Infrastructure Stack
1. **K3s** - Single node Kubernetes cluster (Traefik and ServiceLB disabled)
2. **MetalLB** - Load balancer for bare metal
3. **Ingress-nginx** - Ingress controller
4. **cert-manager** - TLS certificate management
5. **Longhorn** - Distributed block storage for Kubernetes
6. **Prometheus** - Monitoring stack

### Directory Structure
- `charts/` - Custom Helm charts for services
- `values/` - Helmfile values organized by category:
  - `infrastructure/` - Core cluster services
  - `monitoring/` - Monitoring stack configuration
  - `services/` - Self-hosted applications
- `environments/homelab/` - Environment-specific configuration
- `config/` - Application-specific configurations

### Release Dependencies
All self-hosted services depend on:
- `cluster-setup` - Basic cluster resources
- `metallb-addresses` - Load balancer IP pool
- `cert-manager-issuer` - TLS certificate issuer
- `ingress-nginx` - Ingress controller
- `longhorn` - Distributed storage system
- `prometheus` - Monitoring stack

### Namespaces
- `self-hosted` - All self-hosted applications
- `monitoring` - Prometheus, Grafana
- `metallb-system` - MetalLB components
- `ingress` - Ingress controller
- `cert-manager` - Certificate management
- `longhorn-system` - Longhorn storage system

## Configuration Management

### Helmfile Templates
- `default-infrastructure-release` - Infrastructure components
- `default-monitoring-release` - Monitoring services
- `default-self-hosted-release` - Self-hosted applications

### Environment Variables
Key environment settings in `environments/homelab/environment.yaml`:
- Load balancer IP ranges: `10.10.10.100-10.10.10.199`
- Ingress IP: `10.10.10.110`
- Storage path: `/mnt/shared_storage_1`
- Node configurations for K8s cluster

### Custom Charts
Notable custom charts in `charts/`:
- `glance/` - Dashboard service
- `ntfy/` - Notification service
- `sftpgo/` - SFTP server
- `cert-manager-issuer/` - Certificate issuer configuration
- `metallb-addresses/` - Load balancer IP pools

## Service Management

### Adding New Services
1. Create chart in `charts/` or use existing Helm chart
2. Add release to `helmfile.yaml.gotmpl` using appropriate template
3. Create values file in `values/services/`
4. Add version to `environments/homelab/versions.yaml`
5. Apply with `make apply REL=<service-name>`

### Common Service Patterns
- Most services use `default-self-hosted-release` template
- Services with databases typically depend on `postgresql`
- External services use `ingress-customized` chart for custom ingress rules
- Monitoring services use `default-monitoring-release` template

## Infrastructure Notes

### Load Balancer Configuration
- MetalLB provides IP addresses from `10.10.10.100-10.10.10.199`
- Specific services have reserved IPs (see `environment.yaml`)
- Ingress uses `10.10.10.110`

### Storage
- **Longhorn** provides distributed block storage with dynamic provisioning
- Default storage class: `longhorn` (single replica for homelab)
- Storage configured with best-effort data locality
- Legacy local storage classes removed in favor of Longhorn
- Persistent volumes automatically provisioned on demand

### DNS and Networking
- Proxmox nodes configured in DNS hosts
- Services accessible via load balancer IPs
- Cloudflared tunnel for external access
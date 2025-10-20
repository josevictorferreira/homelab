# Technical Architecture

This document outlines the technical architecture of the Homelab Cluster project, a hybrid NixOS/Kubernetes environment designed for self-hosting services with a focus on immutability, GitOps, and high availability.

## 1. Core Philosophy

The architecture is built on three core principles:

- **Immutable Infrastructure**: All system configurations, from the base OS to application deployments, are declarative and version-controlled. This eliminates configuration drift and ensures reproducibility.
- **GitOps**: The Git repository is the single source of truth. All changes to the cluster are made through Git commits, which trigger automated deployment pipelines.
- **High Availability**: The cluster is designed to be resilient to hardware failures, with redundant control planes, distributed storage, and automated failover mechanisms.

## 2. System Layers

The architecture is divided into two main layers: the **NixOS Host Layer** and the **Kubernetes Application Layer**.

### 2.1. NixOS Host Layer

This layer is responsible for managing the underlying hardware and operating system.

- **Operating System**: **NixOS** is used as the operating system for all nodes. Its declarative nature ensures that the entire OS configuration is reproducible and version-controlled.
- **Configuration Management**: All NixOS configurations are managed in the `config/`, `hosts/`, and `modules/` directories.
  - `config/`: Global settings, such as node definitions and user accounts.
  - `hosts/`: Hardware-specific configurations for each node in the cluster.
  - `modules/`: Reusable profiles that define the roles and services for each node (e.g., `k8s-control-plane`, `k8s-worker`).
- **Deployment**: **deploy-rs** is used for remote deployment of NixOS configurations. The `Makefile` provides convenient targets for deploying to individual nodes (`make deploy`) or entire groups of nodes (`make gdeploy`).

### 2.2. Kubernetes Application Layer

This layer is responsible for deploying and managing containerized applications.

- **Kubernetes Distribution**: **k3s** is used as the Kubernetes distribution. It is a lightweight, certified Kubernetes distribution that is easy to install and manage.
- **Manifests**: All Kubernetes manifests are written in **Nix** using **kubenix**, a Nix-based DSL for Kubernetes. This allows for the same level of declarative configuration and type safety as the NixOS layer.
  - The kubenix modules are located in `kubernetes/kubenix/`.
  - The `make manifests` command renders the Nix expressions into standard YAML manifests, which are stored in `kubernetes/manifests/`.
- **GitOps**: **Flux v2** is used for GitOps continuous delivery. Flux monitors the `kubernetes/manifests/` directory in the Git repository and automatically applies any changes to the cluster.
- **Secret Management**: **sops-nix** is used for managing secrets. Secrets are encrypted using `age` and stored directly in the Git repository. The `sops-nix` module decrypts them on the target nodes, making them available to Kubernetes resources.

## 3. Networking

- **CNI**: **Cilium** is used as the Container Network Interface (CNI). It provides advanced networking features, including network policies, load balancing, and observability.
- **API Server High Availability**: **HAProxy** and **Keepalived** are used to provide a highly available Kubernetes API server. A floating virtual IP (VIP) at `10.10.10.250` is used to direct traffic to a healthy control plane node.

## 4. Storage

- **Distributed Storage**: **Rook-Ceph** is used to provide distributed, resilient storage for the cluster. Ceph is a self-healing, self-managing storage platform that provides block, file, and object storage.
- **Storage Pools**: Rook-Ceph manages the physical storage devices on the nodes and creates storage pools that can be consumed by Kubernetes applications.
- **CephFS**: **CephFS** is used to provide a POSIX-compliant shared filesystem for applications that require it.

## 5. High Availability

High availability is achieved through a combination of strategies:

- **Redundant Control Planes**: The cluster has three control plane nodes, ensuring that the Kubernetes API server remains available even if one node fails.
- **Distributed Storage**: Rook-Ceph provides data replication and automatic failover for storage.
- **Automated Failover**: Keepalived and HAProxy ensure that the API server VIP is always pointing to a healthy control plane node.
- **GitOps Recovery**: In the event of a catastrophic failure, the entire cluster can be rebuilt from the Git repository, as all configurations are stored declaratively.

## 6. Development Workflow

The typical development workflow is as follows:

1.  **Modify Configuration**: Make changes to the NixOS configurations (`*.nix`) or Kubernetes manifests (via kubenix).
2.  **Generate Manifests**: If Kubernetes resources were changed, run `make manifests` to generate the YAML manifests.
3.  **Commit and Push**: Commit the changes to the Git repository and push them to the remote.
4.  **Deploy**:
    - For NixOS changes, use `make deploy` or `make gdeploy` to deploy the new configuration to the nodes.
    - For Kubernetes changes, Flux will automatically detect the changes in the Git repository and apply them to the cluster.

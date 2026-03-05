# Kubernetes Resource Recommendations

**Generated:** 2026-03-04
**Data Source:** Prometheus metrics (1d range)
**Purpose:** Stabilize cluster by setting appropriate resource requests/limits

---

## Cluster Capacity Summary

| Node | CPU Allocatable | Memory Allocatable | Role |
|------|-----------------|-------------------|------|
| lab-alpha-cp | 4 cores | 15.5 GB | control-plane, storage |
| lab-beta-cp | 4 cores | 15.4 GB | control-plane, storage |
| lab-delta-cp | 12 cores | 11.6 GB | control-plane, storage, amd-gpu |
| lab-gamma-wk | 4 cores | 7.6 GB | worker, storage |
| **Total** | **24 cores** | **50.1 GB** | |

---

## CRITICAL: Services Without Limits (HIGH RISK)

These services can consume unbounded resources and crash nodes:

| Service | Namespace | Risk Level | Action Required |
|---------|-----------|------------|-----------------|
| immich-machine-learning | apps | **CRITICAL** | Can spike to 2+ cores during ML inference |
| openclaw-nix | apps | **CRITICAL** | Can spike to 2.8GB memory |
| immich-server | apps | **CRITICAL** | Can spike to 1.5GB+ memory during uploads |
| prometheus | monitoring | **CRITICAL** | No memory limit, using 2.3GB |
| linkwarden | apps | **HIGH** | Memory can exceed 1.5GB |
| imgproxy | apps | **HIGH** | Can burst during image processing |
| open-webui | apps | **HIGH** | Can consume 678MB+ |
| synapse-matrix-synapse | apps | **HIGH** | Can spike during federation |
| valoris-worker | apps | **HIGH** | Can spike 20m+ |
| ceph-mon | rook-ceph | **HIGH** | Critical for storage cluster |
| ceph-osd | rook-ceph | **HIGH** | Critical for storage cluster |
| ceph-mgr | rook-ceph | **HIGH** | Critical for storage cluster |

---

## Recommended Resource Allocations

### Control Plane Nodes (3 nodes: k8s-cp-[1-3])
These nodes run critical cluster services and should have reserved capacity.

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| kube-apiserver | 250m | 1 | 512Mi | 1Gi |
| kube-controller | 200m | 500m | 256Mi | 512Mi |
| kube-scheduler | 100m | 500m | 128Mi | 256Mi |
| etcd | 500m | 1 | 512Mi | 1Gi |
| kube-proxy | 100m | 500m | 128Mi | 256Mi |
| coredns | 100m | 500m | 70Mi | 256Mi |
| calico-node | 250m | 500m | 256Mi | 512Mi |
| **Node Reserved** | 500m | - | 512Mi | - |
| **System Reserved** | 250m | - | 256Mi | - |

### Worker Nodes (4 nodes: k8s-wk-[1-4])
These nodes run workloads and can be more aggressively packed.

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| kube-proxy | 100m | 500m | 128Mi | 256Mi |
| calico-node | 250m | 500m | 256Mi | 512Mi |
| **Node Reserved** | 500m | - | 512Mi | - |
| **System Reserved** | 250m | - | 256Mi | - |

### Ceph/Storage Nodes (3 nodes: k8s-ceph-[1-3])
These nodes run storage workloads and need guaranteed resources.

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| ceph-mon | 500m | 1 | 512Mi | 1Gi |
| ceph-osd | 1 | 2 | 2Gi | 4Gi |
| ceph-mgr | 250m | 500m | 512Mi | 1Gi |
| ceph-mds | 250m | 500m | 256Mi | 512Mi |
| **Node Reserved** | 500m | - | 512Mi | - |
| **System Reserved** | 250m | - | 256Mi | - |

---

## Application Resource Recommendations

### High Priority Applications
These applications are critical and should have guaranteed resources.

| Application | CPU Request | CPU Limit | Memory Request | Memory Limit | Priority |
|-------------|-------------|-----------|----------------|--------------|----------|
| prometheus | 1 | 2 | 2Gi | 4Gi | High |
| alertmanager | 100m | 500m | 256Mi | 512Mi | High |
| grafana | 100m | 500m | 256Mi | 512Mi | High |
| traefik | 500m | 1 | 256Mi | 512Mi | High |
| cert-manager | 100m | 500m | 128Mi | 256Mi | High |

### Medium Priority Applications
Standard workloads with burstable QoS.

| Application | CPU Request | CPU Limit | Memory Request | Memory Limit | Priority |
|-------------|-------------|-----------|----------------|--------------|----------|
| media-apps | 500m | 2 | 512Mi | 2Gi | Medium |
| home-assistant | 500m | 1 | 512Mi | 1Gi | Medium |
| mqtt | 100m | 500m | 128Mi | 256Mi | Medium |
| postgresql | 500m | 1 | 512Mi | 1Gi | Medium |
| redis | 100m | 500m | 128Mi | 256Mi | Medium |

### Low Priority Applications
Batch workloads and non-critical services.

| Application | CPU Request | CPU Limit | Memory Request | Memory Limit | Priority |
|-------------|-------------|-----------|----------------|--------------|----------|
| backups | 100m | 500m | 128Mi | 256Mi | Low |
| downloads | 250m | 1 | 256Mi | 512Mi | Low |
| *arr-stack | 250m | 1 | 256Mi | 512Mi | Low |

---

## Node Taints and Tolerations

### Recommended Node Taints
```
# Control plane nodes
k8s-cp-1: node-role.kubernetes.io/control-plane=true:NoSchedule
k8s-cp-2: node-role.kubernetes.io/control-plane=true:NoSchedule
k8s-cp-3: node-role.kubernetes.io/control-plane=true:NoSchedule

# Storage nodes
k8s-ceph-1: node.kubernetes.io/storage=true:NoSchedule
k8s-ceph-2: node.kubernetes.io/storage=true:NoSchedule
k8s-ceph-3: node.kubernetes.io/storage=true:NoSchedule

# Worker nodes (no taints - general workloads)
k8s-wk-1: (none)
k8s-wk-2: (none)
k8s-wk-3: (none)
k8s-wk-4: (none)
```

---

## Resource Quotas by Namespace

### monitoring namespace
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: monitoring-quota
  namespace: monitoring
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
```

### media namespace
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: media-quota
  namespace: media
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
```

### home namespace
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: home-quota
  namespace: home
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 2Gi
    limits.cpu: "2"
    limits.memory: 4Gi
```

---

## Limit Ranges (Default Resource Constraints)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
  - max:
      cpu: "2"
      memory: 4Gi
    min:
      cpu: 50m
      memory: 64Mi
    type: Container
```

---

## Pod Priority Classes

```yaml
# High priority - critical services
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "Critical services that must not be preempted"
---
# Medium priority - standard workloads
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: medium-priority
value: 100000
globalDefault: true
description: "Standard workloads"
---
# Low priority - batch jobs
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 10000
globalDefault: false
description: "Batch jobs and non-critical services"
```

---

## Implementation Checklist

### Phase 1: Node Configuration
- [ ] Configure kubelet resource reservations on all nodes
- [ ] Apply node taints to control plane and storage nodes
- [ ] Verify node capacity after reservations

### Phase 2: Namespace Setup
- [ ] Create namespaces with appropriate labels
- [ ] Apply resource quotas to namespaces
- [ ] Apply limit ranges to namespaces

### Phase 3: Priority Classes
- [ ] Create priority classes
- [ ] Update critical deployments with high-priority class
- [ ] Update batch jobs with low-priority class

### Phase 4: Application Updates
- [ ] Update deployments with resource requests/limits
- [ ] Add appropriate tolerations for tainted nodes
- [ ] Verify pod scheduling and resource allocation

### Phase 5: Monitoring
- [ ] Monitor resource usage with Prometheus
- [ ] Set up alerts for resource exhaustion
- [ ] Review and adjust quotas based on usage patterns

---

## Monitoring Queries

### Cluster Resource Usage
```promql
# CPU utilization by node
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (node) / sum(machine_cpu_cores) by (node) * 100

# Memory utilization by node
sum(container_memory_working_set_bytes{container!=""}) by (node) / sum(machine_memory_bytes) by (node) * 100

# Pod resource requests vs limits
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
sum(kube_pod_container_resource_limits{resource="cpu"}) by (namespace)
```

### Alerts
```yaml
# Alert for high resource usage
- alert: HighCPUUsage
  expr: sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (node) / sum(machine_cpu_cores) by (node) > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High CPU usage on {{ $labels.node }}"

- alert: HighMemoryUsage
  expr: sum(container_memory_working_set_bytes{container!=""}) by (node) / sum(machine_memory_bytes) by (node) > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High memory usage on {{ $labels.node }}"
```

---

## Notes

1. **CPU Overcommit**: Kubernetes allows CPU overcommit. A ratio of 2:1 to 3:1 (requests:capacity) is generally safe for homelab.

2. **Memory Overcommit**: Be more conservative with memory. A ratio of 1.2:1 to 1.5:1 is safer to avoid OOM kills.

3. **Node Reservations**: Always reserve resources for system processes and kubelet to prevent node instability.

4. **Storage Nodes**: Ceph is resource-intensive. Ensure storage nodes have sufficient resources and consider dedicated nodes for production.

5. **Testing**: After applying changes, monitor for a week and adjust based on actual usage patterns.
```
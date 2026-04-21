{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
in
{
  kubernetes.objects = [
    {
      apiVersion = "monitoring.coreos.com/v1";
      kind = "PrometheusRule";
      metadata = {
        name = "cluster-health-alerts";
        inherit namespace;
        labels = {
          "app.kubernetes.io/part-of" = "cluster-health";
          release = "kube-prometheus-stack";
        };
      };
      spec.groups = [
        {
          name = "cluster-health.rules";
          rules = [
            {
              alert = "KubeAPIServerDown";
              expr = "up{job=\"apiserver\"} == 0";
              "for" = "2m";
              labels.severity = "critical";
              annotations = {
                summary = "Kubernetes API server is down";
                description = "KubeAPI server has been unreachable for more than 2 minutes.";
              };
            }
            {
              alert = "KubeletDown";
              expr = "sum by (node)(up{job=\"kubelet\"}) == 0";
              "for" = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "Kubelet is down on {{ $labels.node }}";
                description = "Kubelet has been unreachable on node {{ $labels.node }} for more than 10 minutes.";
              };
            }
            {
              alert = "NodeNotReady";
              expr = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0";
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Node {{ $labels.node }} is not Ready";
                description = "Node {{ $labels.node }} has been NotReady for more than 5 minutes.";
              };
            }
            {
              alert = "NodeMemoryPressure";
              expr = "kube_node_status_condition{condition=\"MemoryPressure\",status=\"true\"} == 1";
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Node {{ $labels.node }} has MemoryPressure";
                description = "Node {{ $labels.node }} is under memory pressure.";
              };
            }
            {
              alert = "NodeDiskPressure";
              expr = "kube_node_status_condition{condition=\"DiskPressure\",status=\"true\"} == 1";
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Node {{ $labels.node }} has DiskPressure";
                description = "Node {{ $labels.node }} is under disk pressure.";
              };
            }
            {
              alert = "KubeDeploymentReplicasMismatch";
              expr = "kube_deployment_status_replicas_available{namespace=~\"apps|rook-ceph|kube-system\"} != kube_deployment_spec_replicas{namespace=~\"apps|rook-ceph|kube-system\"}";
              "for" = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has replicas mismatch";
                description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has {{ $value }} available replicas but desired is {{ $labels.expected_replicas }}.";
              };
            }
            {
              alert = "KubeStatefulSetReplicasMismatch";
              expr = "kube_statefulset_status_replicas_ready{namespace=~\"apps|rook-ceph\"} != kube_statefulset_status_replicas{namespace=~\"apps|rook-ceph\"}";
              "for" = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} replicas mismatch";
                description = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} has {{ $value }} ready replicas but desired is {{ $labels.replicas }}.";
              };
            }
            {
              alert = "PodCrashLooping";
              expr = "increase(kube_pod_container_status_restarts_total[1h]) > 5";
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping";
                description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} has restarted {{ $value }} times in the last hour.";
              };
            }
            {
              alert = "PodTerminatingTooLong";
              expr = "kube_pod_deletion_timestamp > 0";
              "for" = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is terminating too long";
                description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} has been terminating for more than 10 minutes.";
              };
            }
            {
              alert = "EtcdHighRequestLatency";
              expr = "histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m])) > 0.5";
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Etcd high request latency";
                description = "Etcd request latency at 99th percentile is {{ $value }}s, above 0.5s threshold.";
              };
            }
            {
              alert = "EtcdHighErrorRate";
              expr = "rate(etcd_request_errors_total[5m]) > 0.1";
              "for" = "5m";
              #KZ|              labels.severity = "critical";
              annotations = {
                summary = "Etcd high error rate";
                description = "Etcd is seeing {{ $value }} errors per second.";
              };
            }
            {
              alert = "PVCPending";
              expr = "kube_persistentvolume_status_phase{phase=\"Pending\"} == 1";
              "for" = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "PVC {{ $labels.persistentvolume }} is Pending";
                description = "PersistentVolumeClaim {{ $labels.persistentvolume }} has been Pending for more than 10 minutes.";
              };
            }
          ];
        }
      ];
    }
  ];
}

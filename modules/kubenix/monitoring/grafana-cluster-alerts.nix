{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  datasourceUid = "prometheus";
  mkPromRule =
    {
      uid,
      title,
      expr,
      forDuration ? "5m",
      severity ? "critical",
      summary,
      description,
    }:
    {
      inherit uid title;
      condition = "C";
      "for" = forDuration;
      labels = { inherit severity; };
      annotations = { inherit summary description; };
      data = [
        {
          refId = "A";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          inherit datasourceUid;
          model = {
            inherit expr;
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "A";
          };
        }
        {
          refId = "C";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = "__expr__";
          model = {
            type = "threshold";
            expression = "A";
            refId = "C";
            conditions = [
              {
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
              }
            ];
          };
        }
      ];
    };
  alertRules = {
    apiVersion = 1;
    groups = [
      {
        orgId = 1;
        name = "Cluster Health";
        folder = "Cluster Health Alerts";
        interval = "1m";
        rules = [
          (mkPromRule {
            uid = "cluster-kube-apiserver-down";
            title = "KubeAPIServer Down";
            expr = "up{job=\"apiserver\"} == 0";
            forDuration = "2m";
            severity = "critical";
            summary = "Kubernetes API server is down";
            description = "KubeAPI server has been unreachable for more than 2 minutes.";
          })
          (mkPromRule {
            uid = "cluster-kubelet-down";
            title = "Kubelet Down";
            expr = "sum by (node)(up{job=\"kubelet\"}) == 0";
            forDuration = "10m";
            severity = "critical";
            summary = "Kubelet is down on {{ $labels.node }}";
            description = "Kubelet has been unreachable on node {{ $labels.node }} for more than 10 minutes.";
          })
          (mkPromRule {
            uid = "cluster-node-not-ready";
            title = "Node NotReady";
            expr = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0";
            forDuration = "5m";
            severity = "critical";
            summary = "Node {{ $labels.node }} is not Ready";
            description = "Node {{ $labels.node }} has been NotReady for more than 5 minutes.";
          })
          (mkPromRule {
            uid = "cluster-node-memory-pressure";
            title = "Node MemoryPressure";
            expr = "kube_node_status_condition{condition=\"MemoryPressure\",status=\"true\"} == 1";
            forDuration = "5m";
            severity = "warning";
            summary = "Node {{ $labels.node }} has MemoryPressure";
            description = "Node {{ $labels.node }} is under memory pressure. Risk of OOM kills.";
          })
          (mkPromRule {
            uid = "cluster-node-disk-pressure";
            title = "Node DiskPressure";
            expr = "kube_node_status_condition{condition=\"DiskPressure\",status=\"true\"} == 1";
            forDuration = "5m";
            severity = "warning";
            summary = "Node {{ $labels.node }} has DiskPressure";
            description = "Node {{ $labels.node }} is under disk pressure.";
          })
          (mkPromRule {
            uid = "cluster-deployment-replicas-mismatch";
            title = "Deployment Replicas Mismatch";
            expr = "kube_deployment_status_replicas_available{namespace=~\"apps|rook-ceph|kube-system\"} != kube_deployment_spec_replicas{namespace=~\"apps|rook-ceph|kube-system\"}";
            forDuration = "10m";
            severity = "critical";
            summary = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has replicas mismatch";
            description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has {{ $value }} available replicas but desired is {{ $labels.expected_replicas }}.";
          })
          (mkPromRule {
            uid = "cluster-statefulset-replicas-mismatch";
            title = "StatefulSet Replicas Mismatch";
            expr = "kube_statefulset_status_replicas_ready{namespace=~\"apps|rook-ceph\"} != kube_statefulset_status_replicas{namespace=~\"apps|rook-ceph\"}";
            forDuration = "10m";
            severity = "critical";
            summary = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} replicas mismatch";
            description = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} has {{ $value }} ready replicas but desired is {{ $labels.replicas }}.";
          })
          (mkPromRule {
            uid = "cluster-pod-crash-looping";
            title = "Pod Crash Looping";
            expr = "increase(kube_pod_container_status_restarts_total[1h]) > 5";
            forDuration = "5m";
            severity = "warning";
            summary = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping";
            description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} has restarted {{ $value }} times in the last hour.";
          })
          (mkPromRule {
            uid = "cluster-pvcs-pending";
            title = "PVC Pending";
            expr = "kube_persistentvolume_status_phase{phase=\"Pending\"} == 1";
            forDuration = "10m";
            severity = "warning";
            summary = "PVC {{ $labels.persistentvolume }} is Pending";
            description = "PersistentVolumeClaim {{ $labels.persistentvolume }} has been Pending for more than 10 minutes.";
          })
        ];
      }
    ];
  };
in
{
  kubernetes.resources.configMaps."grafana-alerting-cluster-health-rules" = {
    metadata = {
      inherit namespace;
      labels = {
        grafana_alert = "1";
      };
    };
    data."cluster-health-rules.yaml" = kubenix.lib.toYamlStr alertRules;
  };
}

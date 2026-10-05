{
  lib,
  kubenix,
  homelab,
  ...
}:

# Grafana Alloy DaemonSet: tails the logs of every pod in the `apps` namespace
# on its own node through the Kubernetes API (no hostPath, no root) and pushes
# them to Loki (loki.nix).
let
  name = "alloy";
  namespace = homelab.kubernetes.namespaces.monitoring;
  logsNamespace = homelab.kubernetes.namespaces.applications;
  lokiPushUrl = "http://${kubenix.lib.serviceHostFor "loki" namespace}:3100/loki/api/v1/push";

  alloyConfig = ''
    discovery.kubernetes "apps_pods" {
      role = "pod"

      namespaces {
        names = ["${logsNamespace}"]
      }

      // Each DaemonSet pod only tails the pods scheduled on its own node.
      selectors {
        role  = "pod"
        field = "spec.nodeName=" + sys.env("K8S_NODE_NAME")
      }
    }

    discovery.relabel "apps_pods" {
      targets = discovery.kubernetes.apps_pods.targets

      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }

      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }

      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        target_label  = "container"
      }

      rule {
        source_labels = ["__meta_kubernetes_pod_node_name"]
        target_label  = "node"
      }

      // `app` from the `app` label, overridden by app.kubernetes.io/name when set.
      rule {
        source_labels = ["__meta_kubernetes_pod_label_app"]
        regex         = "(.+)"
        target_label  = "app"
      }

      rule {
        source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
        regex         = "(.+)"
        target_label  = "app"
      }
    }

    loki.source.kubernetes "apps_pods" {
      targets    = discovery.relabel.apps_pods.output
      forward_to = [loki.write.loki.receiver]
    }

    loki.write "loki" {
      endpoint {
        url = "${lokiPushUrl}"
      }
    }
  '';
in
{
  # The helm module stamps the release namespace on every object; the Role and
  # RoleBinding the chart renders for `rbac.namespaces` must live in `apps`.
  kubernetes.resources.roles.${name}.metadata.namespace = lib.mkForce logsNamespace;
  kubernetes.resources.roleBindings.${name}.metadata.namespace = lib.mkForce logsNamespace;

  kubernetes.helm.releases.${name} = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://grafana.github.io/helm-charts";
      chart = "alloy";
      version = "1.13.0";
      sha256 = "sha256-3IBQOLROwvwdoErUD/Wo4Fi+/8LnaKoEllWJOYzxbLw=";
    };
    inherit namespace;
    noHooks = true;
    values = {
      # PodLogs CRD is unused; the config above is self-contained.
      crds.create = false;

      # The chart's default ClusterRole can read every Secret in the cluster.
      # Setting `namespaces` makes the chart render a Role in `apps` instead,
      # with only what tailing pod logs needs.
      rbac = {
        namespaces = [ logsNamespace ];
        rules = [
          {
            apiGroups = [ "" ];
            resources = [
              "pods"
              "pods/log"
              "namespaces"
            ];
            verbs = [
              "get"
              "list"
              "watch"
            ];
          }
        ];
      };

      alloy = {
        configMap.content = alloyConfig;
        enableReporting = false;
        mounts.varlog = false;
        resources = {
          requests = {
            cpu = "50m";
            memory = "128Mi";
          };
          limits = {
            cpu = "200m";
            memory = "256Mi";
          };
        };
        securityContext = {
          allowPrivilegeEscalation = false;
          capabilities.drop = [ "ALL" ];
          runAsNonRoot = true;
          runAsUser = 473;
          runAsGroup = 473;
          seccompProfile.type = "RuntimeDefault";
        };
      };

      controller = {
        type = "daemonset";
        tolerations = [
          {
            key = "pi-only";
            operator = "Equal";
            value = "true";
            effect = "NoSchedule";
          }
        ];
      };

      # Chart defaults (10m/50Mi) sit below the monitoring LimitRange minimum.
      configReloader.resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
      };

      serviceMonitor.enabled = true;
    };
  };
}

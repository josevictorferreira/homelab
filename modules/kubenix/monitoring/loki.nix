{
  lib,
  kubenix,
  homelab,
  ...
}:

# Loki (Monolithic mode) storing chunks and index in a Ceph RGW bucket
# provisioned by the `loki-s3` ObjectBucketClaim. Alloy (alloy.nix) ships the
# `apps` namespace pod logs here; Grafana picks the datasource up through its
# sidecar (label `grafana_datasource=1`).
let
  name = "loki";
  namespace = homelab.kubernetes.namespaces.monitoring;
  bucketName = name;
  s3Secret = "${name}-s3";
  retention = "336h"; # 14 days
in
{
  kubernetes = {
    helm.releases.${name} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://grafana-community.github.io/helm-charts";
        chart = "loki";
        version = "18.13.7";
        sha256 = "sha256-TkpN0Qj4fUaAO5r1YT2B3D4DhtltQTxfk7OJztBF+jw=";
      };
      inherit namespace;
      noHooks = true;
      values = {
        deploymentMode = "Monolithic";

        loki = {
          auth_enabled = false;
          commonConfig.replication_factor = 1;

          storage = {
            type = "s3";
            bucketNames.chunks = bucketName;
            s3 = {
              # Loki wants host[:port] here, not a URL; `insecure` selects http.
              endpoint = lib.removePrefix "http://" kubenix.lib.objectStoreEndpoint;
              region = "us-east-1";
              s3ForcePathStyle = true;
              insecure = true;
              # The chart always passes -config.expand-env=true, so these are
              # resolved from the OBC Secret injected via extraEnvFrom below.
              accessKeyId = "\${AWS_ACCESS_KEY_ID}";
              secretAccessKey = "\${AWS_SECRET_ACCESS_KEY}";
            };
          };

          schemaConfig.configs = [
            {
              from = "2026-10-01";
              store = "tsdb";
              object_store = "s3";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];

          limits_config.retention_period = retention;

          compactor = {
            working_directory = "/var/loki/compactor";
            compaction_interval = "10m";
            retention_enabled = true;
            retention_delete_delay = "2h";
            retention_delete_worker_count = 10;
            delete_request_store = "s3";
          };
        };

        singleBinary = {
          replicas = 1;
          extraEnvFrom = [ { secretRef.name = s3Secret; } ];
          persistence = {
            size = "5Gi";
            storageClass = kubenix.lib.defaultStorageClass;
          };
          resources = {
            requests = {
              cpu = "200m";
              memory = "512Mi";
            };
            limits = {
              cpu = "1";
              memory = "1Gi";
            };
          };
          # Single replica: a PDB would only block node drains.
          podDisruptionBudget.enabled = false;
          affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100;
              preference.matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "In";
                  values = [ "lab-alpha-cp" ];
                }
              ];
            }
          ];
        };

        # The chart still defaults the SimpleScalable targets to 3 replicas.
        read.replicas = 0;
        write.replicas = 0;
        backend.replicas = 0;

        # Not needed for a single-tenant monolithic install.
        gateway.enabled = false;
        lokiCanary.enabled = false;
        test.enabled = false;
        chunksCache.enabled = false;
        resultsCache.enabled = false;
        memcached.enabled = false;
        ruler.enabled = false;
        sidecar.rules.enabled = false;

        monitoring.serviceMonitor.enabled = true;
      };
    };

    resources.objectbucketclaim.${s3Secret} = {
      metadata = {
        inherit namespace;
      };
      spec = {
        inherit bucketName;
        storageClassName = "rook-ceph-objectstore";
      };
    };

    objects = [
      {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "${name}-datasource";
          inherit namespace;
          labels.grafana_datasource = "1";
        };
        data."${name}.yaml" = builtins.toJSON {
          apiVersion = 1;
          datasources = [
            {
              name = "Loki";
              type = "loki";
              uid = "loki";
              access = "proxy";
              url = "http://${kubenix.lib.serviceHostFor name namespace}:3100";
              editable = false;
            }
          ];
        };
      }
    ];
  };
}

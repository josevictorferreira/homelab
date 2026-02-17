{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.monitoring;
  minioHost = "10.10.10.209";
  minioPort = 9000;
in

{
  kubernetes.objects = [
    # Headless Service for external MinIO endpoint
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "minio-external";
        namespace = namespace;
        labels = {
          app = "minio-external";
        };
      };
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "metrics";
            port = minioPort;
            targetPort = minioPort;
            protocol = "TCP";
          }
        ];
      };
    }

    # Static Endpoints pointing to MinIO on lab-pi-bk
    {
      apiVersion = "v1";
      kind = "Endpoints";
      metadata = {
        name = "minio-external";
        namespace = namespace;
        labels = {
          app = "minio-external";
        };
      };
      subsets = [
        {
          addresses = [
            { ip = minioHost; }
          ];
          ports = [
            {
              name = "metrics";
              port = minioPort;
              protocol = "TCP";
            }
          ];
        }
      ];
    }

    # ServiceMonitor — cluster metrics
    {
      apiVersion = "monitoring.coreos.com/v1";
      kind = "ServiceMonitor";
      metadata = {
        name = "minio-cluster-metrics";
        namespace = namespace;
        labels = {
          app = "minio-external";
        };
      };
      spec = {
        endpoints = [
          {
            port = "metrics";
            path = "/minio/v2/metrics/cluster";
            interval = "60s";
            scrapeTimeout = "30s";
          }
        ];
        namespaceSelector.matchNames = [ namespace ];
        selector.matchLabels = {
          app = "minio-external";
        };
      };
    }

    # ServiceMonitor — node metrics
    {
      apiVersion = "monitoring.coreos.com/v1";
      kind = "ServiceMonitor";
      metadata = {
        name = "minio-node-metrics";
        namespace = namespace;
        labels = {
          app = "minio-external";
        };
      };
      spec = {
        endpoints = [
          {
            port = "metrics";
            path = "/minio/v2/metrics/node";
            interval = "60s";
            scrapeTimeout = "30s";
          }
        ];
        namespaceSelector.matchNames = [ namespace ];
        selector.matchLabels = {
          app = "minio-external";
        };
      };
    }
  ];
}

{ kubenix, homelab, ... }:

# Prometheus Pushgateway, exposed on a LAN LoadBalancer IP so hosts that
# Prometheus cannot scrape (lab-oci-bk is tailnet-only; pods have no route to
# the tailnet) can push heartbeat metrics instead. Use only for
# push-style heartbeats: pushed series never expire on their own.
let
  name = "pushgateway";
  namespace = homelab.kubernetes.namespaces.monitoring;
  port = 9091;
in
{
  kubernetes.resources.deployments.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      replicas = 1;
      selector.matchLabels.app = name;
      template = {
        metadata.labels.app = name;
        spec = {
          containers = [
            {
              inherit name;
              image = "quay.io/prometheus/pushgateway:v1.11.3";
              ports = [
                {
                  name = "http";
                  containerPort = port;
                  protocol = "TCP";
                }
              ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "128Mi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
              };
              readinessProbe = {
                httpGet = {
                  path = "/-/ready";
                  inherit port;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
            }
          ];
        };
      };
    };
  };

  kubernetes.resources.services.${name} = {
    metadata = {
      inherit name namespace;
      labels.app = name;
      annotations = kubenix.lib.serviceAnnotationFor name;
    };
    spec = {
      type = "LoadBalancer";
      selector.app = name;
      ports = [
        {
          name = "http";
          inherit port;
          targetPort = port;
          protocol = "TCP";
        }
      ];
    };
  };

  kubernetes.objects = [
    {
      apiVersion = "monitoring.coreos.com/v1";
      kind = "ServiceMonitor";
      metadata = {
        inherit name namespace;
        labels.app = name;
      };
      spec = {
        endpoints = [
          {
            port = "http";
            interval = "60s";
            # Keep the job/instance labels the pusher set instead of the
            # pushgateway's own.
            honorLabels = true;
          }
        ];
        namespaceSelector.matchNames = [ namespace ];
        selector.matchLabels.app = name;
      };
    }
  ];
}

{
  kubenix,
  homelab,
  pkgs,
  ...
}:

let
  app = "uptimekuma";
  namespace = homelab.kubernetes.namespaces.applications;
  chartVersion = "2.22.0";
  upstreamChart = kubenix.lib.helm.fetch {
    repo = "https://helm.irsigler.cloud/";
    chart = "uptime-kuma";
    version = chartVersion;
    sha256 = "sha256-eh42cO0bFiMNYIpXJSHkGQVnGsn4cmv6ju8VjYu8YYU=";
  };
  patchedChart = pkgs.runCommand "uptime-kuma-${chartVersion}-replicas-chart" { } ''
    cp -R ${upstreamChart} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/templates/deployment.yaml" \
      --replace-fail "replicas: 1" "replicas: {{ if hasKey .Values \"replicas\" }}{{ .Values.replicas }}{{ else }}1{{ end }}"
    substituteInPlace "$out/templates/statefulset.yaml" \
      --replace-fail "replicas: 1" "replicas: {{ if hasKey .Values \"replicas\" }}{{ .Values.replicas }}{{ else }}1{{ end }}"
  '';
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = patchedChart;
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        replicas = 0;
        priorityClassName = "preemptible";
        image = {
          repository = "louislam/uptime-kuma";
          pullPolicy = "IfNotPresent";
          tag = "2.2.1@sha256:7337368a77873f159435de9ef09567f68c31285ed5f951dec36256c4b267ee44";
        };

        tolerations = [
          {
            key = "pi-only";
            operator = "Equal";
            value = "true";
            effect = "NoSchedule";
          }
        ];
        affinity = homelab.kubernetes.affinities.piNode;

        volume = {
          storageClassName = kubenix.lib.defaultStorageClass;
        };

        ingress = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          annotations = kubenix.lib.serviceAnnotationFor app;
          hosts = [
            {
              host = kubenix.lib.domainFor "uptimekuma";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [ (kubenix.lib.domainFor "uptimekuma") ];
              secretName = kubenix.lib.defaultTLSSecret;
            }
          ];
        };
      };
    };
  };
}

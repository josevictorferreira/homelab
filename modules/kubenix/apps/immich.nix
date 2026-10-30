{ kubenix, homelab, pkgs, ... }:

let
  # Use root PVC with subPath to avoid overlapping CephFS mount issues
  immichLibraryPVC = kubenix.lib.sharedStorage.rootPVC;
  app = "immich";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      # Since 0.11 the chart and its bjw-s common subchart $ref JSON schemas on
      # raw.githubusercontent.com, which helm cannot fetch inside the Nix
      # sandbox; drop those schema files so `helm template` can run.
      chart = pkgs.runCommand "immich-chart" { } ''
        cp -r ${kubenix.lib.helm.fetch {
          chartUrl = "oci://ghcr.io/immich-app/immich-charts/immich";
          chart = "immich";
          version = "0.13.4";
          sha256 = "sha256-Nj9kifEjGhulJ2+9ktv58wAFYiCLuxH9Q04TOyKC4x8=";
        }} $out
        chmod -R u+w $out
        grep -rl --include=values.schema.json 'https://' $out | xargs -r rm
      '';
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        controllers.main.containers.main = {
          env = { };
          envFrom = [
            {
              secretRef = {
                name = "immich-secret";
              };
            }
          ];
        };

        immich = {
          persistence.library = {
            existingClaim = immichLibraryPVC;
          };

          configuration = {
            trash.enabled = true;
            trash.days = 30;
            # No machine-learning pod deployed; keep the server from queueing
            # smart-search/face-detection jobs against a service that is gone.
            machineLearning.enabled = false;
          };

          metrics.enabled = true;
        };

        # Disabled: the inference workload is too compute intensive for this cluster.
        machine-learning.enabled = false;

        server = {
          enabled = true;
          controllers.main = {
            replicas = 1;
            pod.priorityClassName = "preemptible";
          };
          controllers.main.containers.main = {
            image = {
              repository = "ghcr.io/immich-app/immich-server";
              tag = "v3.3.5@sha256:485d546a2e31d6a8b4db8423fcba5c109de8c218d93410af115fd1ccfc4352a6";
              pullPolicy = "IfNotPresent";
            };
            resources = {
              requests = {
                cpu = "100m";
                memory = "512Mi";
              };
              limits = {
                cpu = "500m";
                memory = "2Gi";
              };
            };
          };

          service.main = {
            enabled = true;
            type = "LoadBalancer";
            annotations = kubenix.lib.serviceAnnotationFor app;
          };

          ingress.main = {
            enabled = true;
            className = kubenix.lib.defaultIngressClass;
            hosts = [
              {
                host = kubenix.lib.domainFor app;
                paths = [
                  {
                    path = "/";
                    service.name = "immich-server";
                    service.port = 2283;
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = kubenix.lib.defaultTLSSecret;
                hosts = [ (kubenix.lib.domainFor app) ];
              }
            ];
          };
        };
      };
    };
  };
}

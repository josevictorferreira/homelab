{ kubenix, homelab, ... }:

let
  k8s = homelab.kubernetes;
  app = "ollama";
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.otwld.com/";
        chart = "ollama";
        version = "1.32.0";
        sha256 = "sha256-+4u6sYLNy1jVccN2LRRT86N+dqP1SSBWA+o6HSWfO2o=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = k8s.namespaces.applications;
      values = {
        image = {
          repository = "ghcr.io/josevictorferreira/ollama";
          tag = "0.12.6-1-g7f551c4-dirty-rocm@d1d265d065204ff56dfc7dd2eae5010eeace889bd3bde2bc44d05ecbbd85a638";
          pullPolicy = "IfNotPresent";
        };

        ollama = {
          gpu = {
            enabled = true;
            type = "amd";
          };

          models = {
            pull = [
              "qwen3-embedding:0.6b"
              "embeddinggemma:300m"
              "dimavz/whisper-tiny"
            ];

            run = [
              "qwen3-embedding:0.6b"
              "dimavz/whisper-tiny"
            ];

            clean = true;
          };
        };

        extraEnv = [
          {
            name = "HSA_OVERRIDE_GFX_VERSION";
            value = "9.0.0";
          }
          {
            name = "OLLAMA_DEBUG";
            value = "2";
          }
        ];

        nodeSelector = {
          "node.kubernetes.io/amd-gpu" = "true";
        };

        tolerations = [
          {
            key = "node-role.kubernetes.io/control-plane";
            operator = "Exists";
            effect = "NoSchedule";
          }
        ];

        service = {
          annotations = kubenix.lib.serviceAnnotationFor app;
          type = "LoadBalancer";
          loadBalancerIP = homelab.kubernetes.loadBalancer.services.${app};
        };

        resources = {
          requests = {
            "amd.com/gpu" = "1";
            memory = "1Gi";
          };
          limits = {
            "amd.com/gpu" = "1";
            memory = "4Gi";
          };
        };

        persistentVolume = {
          enabled = true;
          size = "60Gi";
          storageClass = "rook-ceph-block";
        };
      };
    };
  };
}

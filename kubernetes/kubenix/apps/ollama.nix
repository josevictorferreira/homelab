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
          repository = "ollama/ollama";
          tag = "rocm@sha256:4f1a40333f4a505e2eccc205c19b23f8730fd47be456bf04063d967e8ebb6dbe";
          pullPolicy = "IfNotPresent";
        };

        ollama = {
          gpu = {
            enabled = true;
            type = "amd";
          };

          models = {
            # pull = [
            #   "qwen3-embedding:0.6b"
            #   "embeddinggemma:300m"
            #   "dimavz/whisper-tiny"
            # ];
            #
            # run = [
            #   "qwen3-embedding:0.6b"
            #   "dimavz/whisper-tiny"
            # ];

            clean = true;
          };
        };

        extraEnv = [
          {
            name = "HSA_OVERRIDE_GFX_VERSION";
            value = "9.0.8";
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

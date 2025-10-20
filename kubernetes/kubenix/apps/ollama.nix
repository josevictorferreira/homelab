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
            number = 1;
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
          # {
          #   name = "LD_LIBRARY_PATH";
          #   value = "/opt/rocm/lib:/run/opengl-driver/lib:/usr/lib/ollama/rocm";
          # }
          # {
          #   name = "PATH";
          #   value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/rocm/bin";
          # }
          {
            name = "HCC_AMDGPU_TARGET";
            value = "gfx1030";
          }
          {
            name = "HSA_OVERRIDE_GFX_VERSION";
            value = "10.3.0";
          }
          # {
          #   name = "OLLAMA_GPU_LAYERS";
          #   value = "32";
          # }
          # {
          #   name = "OLLAMA_NUM_PARALLEL";
          #   value = "4";
          # }
          {
            name = "OLLAMA_DEBUG";
            value = "2";
          }
          # {
          #   name = "ROCM_PATH";
          #   value = "/opt/rocm";
          # }
          # {
          #   name = "ROCM_VISIBLE_DEVICES";
          #   value = "0";
          # }
          # {
          #   name = "HIP_VISIBLE_DEVICES";
          #   value = "0";
          # }
        ];

        service = {
          annotations = kubenix.lib.serviceAnnotationFor app;
          type = "LoadBalancer";
          loadBalancerIP = homelab.kubernetes.loadBalancer.services.${app};
        };

        resources.limits = {
          "amd.com/gpu" = "1";
        };

        persistentVolume = {
          enabled = true;
          size = "60Gi";
          storageClass = "rook-ceph-block";
        };
        #
        # volumeMounts = [
        #   {
        #     name = "dev-kfd";
        #     mountPath = "/dev/kfd";
        #   }
        #   {
        #     name = "dev-dri";
        #     mountPath = "/dev/dri";
        #   }
        #   {
        #     name = "rocm";
        #     mountPath = "/opt/rocm";
        #   }
        #   {
        #     name = "opengl-driver";
        #     mountPath = "/run/opengl-driver";
        #     readOnly = true;
        #   }
        #   {
        #     name = "nix-glibc";
        #     mountPath = "/nix/store";
        #   }
        # ];

        # volumes = [
          # {
          #   name = "dev-kfd";
          #   hostPath = {
          #     path = "/dev/kfd";
          #     type = "CharDevice";
          #   };
          # }
          # {
          #   name = "dev-dri";
          #   hostPath = {
          #     path = "/dev/dri";
          #     type = "Directory";
          #   };
          # }
          # {
          #   name = "rocm";
          #   hostPath = {
          #     path = "/opt/rocm";
          #     type = "Directory";
          #   };
          # }
          # {
          #   name = "opengl-driver";
          #   hostPath = {
          #     path = "/run/opengl-driver";
          #     type = "Directory";
          #   };
          # }
          # {
          #   name = "nix-glibc";
          #   hostPath = {
          #     path = "/nix/store";
          #     type = "Directory";
          #   };
          # }
        # ];

      };
    };
  };
}

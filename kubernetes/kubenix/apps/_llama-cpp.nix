{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "llama-cpp";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/ggml-org/llama.cpp";
        tag = "server-vulkan@sha256:429a5c2109a15b33026d5dcc2333b6cb89a58a3566c7b6ad84891c95e4a4416b";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
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
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
        size = "30Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/models";
            readOnly = false;
          }
        ];
      };
    };
  };
}

{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "whisperwebui";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/jhj0517/whisper-webui-backend";
        tag = "v1.0.7@sha256:4b4ebc76d5efe57247e1136bb857ed0f374a6b471e0d4d25ea42c3874e374160";
        pullPolicy = "IfNotPresent";
      };
      subdomain = app;
      port = 8000;
      resources = {
        requests = {
          memory = "256Mi";
          cpu = "30m";
        };
        limits = {
          "amd.com/gpu" = "1";
        };
      };
      command = [
        "uvicorn"
        "backend.main:app"
        "--host"
        "0.0.0.0"
        "--port"
        "8000"
      ];
      persistence = {
        enabled = true;
        size = "5Gi";
        storageClass = "rook-ceph-block";
        type = "persistentVolumeClaim";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/Whisper-WebUI/models";
            readOnly = false;
          }
        ];
      };
    };
  };
}

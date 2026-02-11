{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.openclaw = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/openclaw/openclaw";
        tag = "latest@sha256:a02b8193cc9d985dce3479eb1986a326f1e28253275b1c43491ac7923d6167e5";
        pullPolicy = "IfNotPresent";
      };
      port = 18789;
      replicas = 1;
      secretName = "openclaw-secrets";
      command = [
        "node"
        "dist/index.js"
        "gateway"
        "--allow-unconfigured"
      ];
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
        size = "10Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [ { path = "/home/node/.openclaw"; } ];
      };
      config = {
        filename = "openclaw.json";
        mountPath = "/home/node/.openclaw";
        data = {
          gateway = {
            port = 18789;
            bind = "0.0.0.0";
          };
          logging = {
            level = "info";
          };
        };
      };
      values = {
        ingress.main.enabled = false;
      };
    };
  };
}

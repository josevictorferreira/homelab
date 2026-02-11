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
      # Config mounted to /config, then copied by initContainer to PVC
      config = {
        filename = "openclaw.json";
        mountPath = "/config";
        data = {
          gateway = {
            port = 18789;
            bind = "lan";
          };
          logging = {
            level = "info";
          };
        };
      };
      values = {
        ingress.main.enabled = false;
        # InitContainer copies config from ConfigMap to PVC
        controllers.main.initContainers.copy-config = {
          image = {
            repository = "busybox";
            tag = "latest";
          };
          command = [
            "sh"
            "-c"
            "cp /config/openclaw.json /home/node/.openclaw/openclaw.json && chown 1000:1000 /home/node/.openclaw/openclaw.json"
          ];
        };
      };
    };
  };
}

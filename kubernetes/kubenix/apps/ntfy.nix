{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.ntfy = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "docker.io/binwiederhier/ntfy";
        tag = "v2.14.0@sha256:5a051798d14138c3ecb12c038652558ab6a077e1aceeb867c151cbf5fa8451ef";
        pullPolicy = "IfNotPresent";
      };
      subdomain = "ntfy";
      port = 80;
      secretName = "ntfy-secrets";
      persistence = {
        enabled = true;
        type = "persistentVolumeClaim";
        storageClass = "rook-ceph-block";
        size = "1Gi";
        accessMode = "ReadWriteOnce";
        globalMounts = [
          {
            path = "/data";
            readOnly = false;
          }
        ];
      };
    };
  };
}

{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.scriberr = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/rishikanthc/scriberr";
        tag = "v1.1.0@sha256:99a0b29003e046c08e5aad102fb4a01d28a298dbd3889819bcfb760a75cbfef6";
        pullPolicy = "IfNotPresent";
      };
      subdomain = "scriberr";
      port = 8080;
      values = {
        persistence = {
          main = {
            enabled = true;
            size = "5Gi";
            storageClass = "rook-ceph-block";
            type = "persistentVolumeClaim";
            accessMode = "ReadWriteOnce";
            globalMounts = [
              {
                path = "/app/data";
                readOnly = false;
              }
            ];
          };
        };
      };
    };
  };
}

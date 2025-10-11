{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.libebooker = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/libebooker";
        tag = "latest";
        pullPolicy = "IfNotPresent";
      };
      port = 9292;
    };
  };
}

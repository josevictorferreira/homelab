{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "mcpo";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/mcpo";
        tag = "latest@sha256:2b9fd131273b4ac53bfc9c2ff32f85e5898563d4f4704c8cd0af53f7f2ae1d85";
        pullPolicy = "IfNotPresent";
      };
      port = 8000;
    };
  };
}

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
        tag = "latest";
        pullPolicy = "Always";
      };
      port = 8000;
    };
  };
}

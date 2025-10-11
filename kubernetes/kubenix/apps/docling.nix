{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "docling";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/docling-project/docling-serve";
        tag = "v1.6.0@sha256:7dc85167c6f9175b8380e54e6fb759654d3c2339edef3b878a9199d651c0e59b";
        pullPolicy = "IfNotPresent";
      };
      port = 5001;
      values = {
        defaultPodOptions = {
          nodeSelector = {
            "node.kubernetes.io/amd-gpu" = "true";
          };
        };
      };
    };
  };
}

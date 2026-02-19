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
        tag = "latest@sha256:87bf1da9ed289777a08e4e5816cc9f8a9df5cee259842ac5ff3a223f0256ecc2";
        pullPolicy = "IfNotPresent";
      };
      port = 8000;
    };
  };
}

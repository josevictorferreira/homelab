{ homelab, ... }:

let
  app = "youtube-transcriber";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/youtube-transcriber";
        tag = "0.0.1@sha256:13510480faf6e70c5d02b2623cf4192c03f52f246d9d00415e4a1a75326c95bd";
        pullPolicy = "IfNotPresent";
      };
      subdomain = app;
      port = 8080;
    };
  };
}

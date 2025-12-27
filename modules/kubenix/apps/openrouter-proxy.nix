{ ... }:

let
  app = "openrouter-proxy";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = {
        repository = "ghcr.io/josevictorferreira/openrouter-proxy";
        tag = "v0.0.5";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      secretName = "openrouter-secrets";
    };
  };
}

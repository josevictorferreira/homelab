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
        tag = "v0.0.3@sha256:ac96756841bc22c2b573727404d75047eec93dc9e50cbb8778daf2205dc1b899";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      secretName = "openrouter-secrets";
    };
  };
}

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
        tag = "v0.0.1@sha256:9de5646897629f99534068132e452608dbaf62c84d8c77ed3300f7340057e6bc";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      secretName = "openrouter-secrets";
    };
  };
}

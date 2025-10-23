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
        tag = "v0.0.2@sha256:15148111418dbd735ed3c7633e2598b78fcb47a12521c0413a6614adf0c84148";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      secretName = "openrouter-secrets";
    };
  };
}

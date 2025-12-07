{ ... }:

let
  imageTag = "main-0d03b75";
in
{
  submodules.instances = {
    valoris = {
      submodule = "release";
      args = {
        namespace = "apps";
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-server";
          tag = imageTag;
          pullPolicy = "IfNotPresent";
        };
        secretName = "valoris-config";
        port = 3000;
        values = {
          defaultPodOptions.imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
        };
      };
    };
    valoris-worker = {
      submodule = "release";
      args = {
        namespace = "apps";
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-worker";
          tag = imageTag;
          pullPolicy = "IfNotPresent";
        };
        secretName = "valoris-config";
        port = 3000;
        values = {
          defaultPodOptions.imagePullSecrets = [
            { name = "ghcr-registry-secret"; }
          ];
        };
      };
    };
  };
}

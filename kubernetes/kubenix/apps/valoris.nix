{ ... }:

let
  imageTag = "latest";
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
          pullPolicy = "Always";
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
          pullPolicy = "Always";
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

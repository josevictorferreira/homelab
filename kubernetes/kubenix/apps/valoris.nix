{ ... }:

{
  submodules.instances = {
    valoris = {
      submodule = "release";
      args = {
        namespace = "apps";
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-server";
          tag = "main-df35547";
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
          tag = "main-df35547";
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

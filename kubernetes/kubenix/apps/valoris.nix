{ ... }:

{
  submodules.instances = {
    valoris = {
      submodule = "release";
      args = {
        namespace = "apps";
        image = {
          repository = "josevictorferreira/valoris-server";
          tag = "latest";
          pullPolicy = "IfNotPresent";
        };
        secretName = "valoris-secret";
        port = 3000;
      };
    };
    valoris-worker = {
      submodule = "release";
      args = {
        namespace = "apps";
        image = {
          repository = "josevictorferreira/valoris-worker";
          tag = "latest";
          pullPolicy = "IfNotPresent";
        };
        secretName = "valoris-secret";
        port = 3000;
      };
    };
  };
}

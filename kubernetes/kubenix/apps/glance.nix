{ ... }:

{
  submodules.instances.glance = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = {
        repository = "glanceapp/glance";
        tag = "v0.8.4@sha256:6df86a7e8868d1eda21f35205134b1962c422957e42a0c44d4717c8e8f741b1a";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      config = {
        filename = "glance.yml";
        mountPath = "/app/config";
      };
    };
  };
}

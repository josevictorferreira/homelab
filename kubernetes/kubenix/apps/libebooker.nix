{ clusterLib, ... }:

{
  submodules.instances.libebooker = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = {
        repository = "ghcr.io/josevictorferreira/libebooker";
        tag = "latest";
        pullPolicy = "IfNotPresent";
      };
      subdomain = "libebooker";
      port = 9292;
      values = {
        service.main = {
          type = "LoadBalancer";
          annotations = clusterLib.serviceIpFor "libebooker";
          ports = {
            http = {
              enabled = true;
              port = 9292;
            };
          };
        };
      };
    };
  };
}

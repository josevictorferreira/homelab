{ clusterConfig, ... }:

{
  submodules.instances.libebooker = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = "ghcr.io/josevictorferreira/libebooker:latest";
      subdomain = "libebooker";
      port = 9292;
      values = {
        service.main = {
          type = "LoadBalancer";
          loadBalancerIP = clusterConfig.loadBalancer.services.libebooker;
          ports = {
            http = {
              enabled = true;
              port = 9292;
            };
          };
        };
        configMaps.config = {
          enabled = false;
        };
      };
    };
  };
}

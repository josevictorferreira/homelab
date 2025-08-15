{ clusterConfig, ... }:

{
  submodules.instances.glance = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = "ghcr.io/josevictorferreira/libebooker:latest";
      subdomain = "libebooker";
      port = 9292;
      values = {
        controllers.main.containers.main = {
          image = {
            repository = "ghcr.io/josevictorferreira/libebooker:latest";
            tag = "latest";
            pullPolicy = "IfNotPresent";
          };
          ports = [
            {
              name = "http";
              containerPort = 9292;
              protocol = "TCP";
            }
          ];
        };
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

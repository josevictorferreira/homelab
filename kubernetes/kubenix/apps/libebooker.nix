{ kubenix, labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.applications;
in
{
  submodules.instances.libebooker = {
    submodule = "release";
    args = {
      namespace = namespace;
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
          annotations = kubenix.lib.serviceIpFor "libebooker";
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

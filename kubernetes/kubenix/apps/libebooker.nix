{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
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
          annotations = kubenix.lib.serviceAnnotationFor "libebooker";
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

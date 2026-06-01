{ homelab, ... }:

{
  submodules.instances.glance = {
    submodule = "release";
    args = {
      namespace = homelab.kubernetes.namespaces.applications;
      image = {
        repository = "glanceapp/glance";
        tag = "v0.8.5@sha256:32ab73d80f2b8b5fb0735b0431deb36b93fbb6b2fb43592449b0178c8b83e350";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "256Mi";
        };
      };
      config = {
        filename = "glance.yml";
        mountPath = "/app/config";
      };
    };
  };
}

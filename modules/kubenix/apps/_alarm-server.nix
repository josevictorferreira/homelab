{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.alarm-server = {
    submodule = "release";
    args = {
      namespace = namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/alarm-server";
        tag = "v0.2.3@sha256:317714c3c6d0939cc89aef10b00cee5dde4dd455b820c98d6cc9dbddc1552626";
        pullPolicy = "IfNotPresent";
      };
      port = 8888;
      secretName = "alarm-server-config";
      resources = {
        requests = {
          memory = "256Mi";
          cpu = "30m";
        };
        limits = {
          memory = "512Mi";
        };
      };
    };
  };
}

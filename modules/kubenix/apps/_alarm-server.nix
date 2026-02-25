{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  submodules.instances.alarm-server = {
    submodule = "release";
    args = { inherit namespace; };
  };
}

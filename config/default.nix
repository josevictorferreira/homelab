{ lib, ... }:
let
  t = lib.types;
  homelab = {
    project = import ./project.nix { inherit lib; };
    users = import ./users.nix;
    cluster = import ./cluster.nix { inherit lib; };
    kubernetes = import ./kubernetes.nix { inherit lib; labConfig = homelab; };
  };
in
{
  options.homelab = lib.mkOption {
    type = t.attrs;
    description = "Unified homelab configuration (cluster + k8s + users).";
  };

  config =
    {
      homelab = homelab;
      _module.args.labConfig = homelab;
    };
}

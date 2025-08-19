{ lib, ... }:
let
  t = lib.types;
  repoPathVariableName = "HOMELAB_REPO_PATH";
  repoPathEnv = builtins.getEnv repoPathVariableName;
  repoPathFromFile = ./..;
  repoRoot = if repoPathEnv != "" then repoPathEnv else repoPathFromFile;
  users = import ./users.nix;
  cluster = import ./cluster.nix;
  kubernetes = import ./kubernetes.nix;
  project = {
    name = "ze-homelab";

    paths = rec {
      root = repoRoot;
      commons = "${root}/modules/commons";
      profiles = "${root}/modules/profiles";
      programs = "${root}/modules/programs";
      services = "${root}/modules/services";
      kubernetes = "${root}/kubernetes";
      kubenix = "${root}/kubenix";
      manifests = "${kubernetes}/manifests";
      secrets = "${root}/secrets";
      config = "${root}/config";
      lib = "${root}/lib";
    };
    inherit project users cluster kubernetes;
  };
in
{
  options.project = lib.mkOption {
    type = t.attrs;
    description = "Unified homelab project configurations (cluster + k8s + users).";
  };

  config =
    {
      project = project;
      _module.args.project = project;
    };
}

{ ... }:

let
  repoPathVariableName = "HOMELAB_REPO_PATH";
  repoPathEnv = builtins.getEnv repoPathVariableName;
  repoPathFromFile = ./..;
  repoRoot = if repoPathEnv != "" then repoPathEnv else repoPathFromFile;
in
{
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
    lib = "${root}/lib";
    config = "${root}/config";
  };
}

{ lib, ... }:

let
  repoPathVariableName = "HOMELAB_REPO_PATH";
  repoPathEnv = builtins.getEnv repoPathVariableName;
  repoPathFromFile = ./..;
  repoRoot = if repoPathEnv != "" then repoPathEnv else repoPathFromFile;
  users = (import ./users.nix { inherit lib; });
  cluster = (import ./cluster.nix { inherit lib; });
  kubernetes = (import ./kubernetes.nix { inherit lib; });
in
{
  name = "ze-homelab";

  domain = "josevictor.me";

  timeZone = "America/Sao_Paulo";

  gateway = "10.10.10.1";

  dnsServers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  paths = rec {
    root = repoRoot;
    commons = "${root}/modules/common";
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

  inherit users cluster kubernetes;
}

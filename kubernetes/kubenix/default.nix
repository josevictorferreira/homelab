{ lib, flake, clusterConfig, kubenix, ... }:

let
  repoPathVariableName = "HOMELAB_REPO_PATH";
  repoPathEnv = builtins.getEnv repoPathVariableName;
  repoRoot = if repoPathEnv != "" then repoPathEnv else flake.flakeRoot;
  k8sSecretsFile = "${repoRoot}/secrets/k8s-secrets.enc.yaml";

  isModuleFile = name:
    lib.hasSuffix ".nix" name
    && name != "default.nix"
    && !(lib.hasPrefix "_" name);

  discover = dir: rel:
    let
      entries = builtins.readDir dir;
      items = lib.mapAttrsToList (name: type: { inherit name type; }) entries;

      files = lib.filter (e: e.type == "regular" && isModuleFile e.name) items;
      dirs = lib.filter (e: e.type == "directory") items;

      here = map
        (e: {
          path = builtins.toPath "${dir}/${e.name}";
          rel = if rel == "" then e.name else "${rel}/${e.name}";
        })
        files;

      below = lib.concatMap
        (e:
          discover
            (builtins.toPath "${dir}/${e.name}")
            (if rel == "" then e.name else "${rel}/${e.name}")
        )
        dirs;
    in
    here ++ below;

  hasIgnoredSegment = rel:
    let segs = lib.splitString "/" rel;
    in builtins.any (seg: lib.hasPrefix "_" seg) segs;

  modules =
    let ds = discover ./. "";
    in lib.filter (m: !(hasIgnoredSegment m.rel)) ds;

  secretsFor = secretName: "ref+sops://${k8sSecretsFile}#${secretName}";

  baseModule = { kubenix, ... }: {
    imports = with kubenix.modules; [
      helm
      k8s
      submodules
      ./_submodules/release.nix
    ];

    kubenix.project = clusterConfig.name;

    kubernetes = {
      version = "1.32";
    };
  };

  evalModule = system: filePath:
    (kubenix.evalModules.${system} {
      modules = [
        baseModule
        filePath
      ];
      specialArgs = {
        inherit flake kubenix clusterConfig secretsFor;
      };
    }).config.kubernetes.resultYAML;

  mkRenderer = system: pkgs:
    let
      copyCmds = lib.concatStringsSep "\n" (map
        (m:
          let
            dest = "${lib.removeSuffix ".nix" m.rel}.yaml";
          in
          ''
            install -D -m 0755 ${evalModule system m.path} "$out/${dest}"
            chmod 0644 "$out/${dest}"
            echo "Copied ${m.rel} to $out/${dest}"
          ''
        )
        modules);
    in
    pkgs.runCommand "gen-k8s-manifests" { } ''
      set -euo pipefail
      mkdir -p "$out"
      ${copyCmds}
    '';
in
{
  inherit modules evalModule mkRenderer;
}

# kubernetes/kubenix/default.nix
{ lib, kubenix, clusterConfig }:

let
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

  modules = discover ./. "";

  evalModule = system: filePath:
    (kubenix.evalModules.${system} {
      modules = [ (import filePath) ];
      specialArgs = { inherit kubenix clusterConfig; };
    }).config.kubernetes.resultYAML;

  mkRenderer = system: pkgs:
    let
      copyCmds = lib.concatStringsSep "\n" (map
        (m:
          let dest = "${lib.removeSuffix ".nix" m.rel}.yaml";
          in ''
            install -D -m 0755 ${evalModule system m.path} "$out/${dest}"
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

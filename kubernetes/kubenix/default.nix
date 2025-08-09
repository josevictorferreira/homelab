{ lib, kubenix, clusterConfig }:

let
  inherit (builtins) readDir toPath;
  root = ./.;

  discover = dir:
    let
      entries = readDir dir;
      items = lib.mapAttrsToList (name: type: { inherit name type; }) entries;

      files = lib.filter
        (e: e.type == "regular"
          && lib.hasSuffix ".nix" e.name
          && e.name != "default.nix"
          && !(lib.hasPrefix "_" e.name))
        items;

      dirs = lib.filter (e: e.type == "directory") items;

      here = map
        (e: {
          path = toPath "${dir}/${e.name}";
          rel = lib.removePrefix (toString root + "/") "${dir}/${e.name}";
        })
        files;

      below = lib.concatMap (e: discover (toPath "${dir}/${e.name}")) dirs;
    in
    here ++ below;

  modules = discover root;

  evalModule = system: filePath:
    (kubenix.evalModules.${system} {
      modules = [ (import filePath) ];
      specialArgs = {
        inherit kubenix clusterConfig;
      };
    }).config.kubernetes.resultYAML;

  mkRenderer = system: pkgs:
    let
      cmds = lib.concatStringsSep "\n" (map
        (m: ''
          mkdir -p "$out/${lib.dirOf m.rel}"
          cp ${evalModule system m.path} "$out/${lib.removeSuffix ".nix" m.rel}.yaml"
        '')
        modules);
    in
    pkgs.runCommand "gen-k8s-manifests" { } ''
      set -eu
      mkdir -p "$out"
      ${cmds}
    '';
in
{
  inherit modules evalModule mkRenderer;
}

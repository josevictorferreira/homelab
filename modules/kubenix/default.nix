{ lib, pkgs, kubenix, homelab, ... }:

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
          path = builtins.toString "${dir}/${e.name}";
          rel = if rel == "" then e.name else "${rel}/${e.name}";
        })
        files;

      below = lib.concatMap
        (e:
          discover
            (builtins.toString "${dir}/${e.name}")
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

  kubenixModule = kubenix // {
    lib = (import (kubenix + "/lib/default.nix") {
      inherit lib pkgs;
    }) // (import ./_lib { inherit pkgs homelab; });
  };

  evalModule = system: filePath:
    (kubenixModule.evalModules.${system} {
      modules = [
        ./_base.nix
        filePath
      ];
      specialArgs = {
        kubenix = kubenixModule;
        inherit homelab;
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
  inherit mkRenderer;
}

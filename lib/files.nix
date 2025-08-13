{ lib, pkgs }:

with lib;
let
  self = {
    importYAML = path:
      importJSON (pkgs.runCommand "yaml-to-json" { } ''
        ${pkgs.yq}/bin/yq -c . ${path} > $out
      '');
  };
in
self

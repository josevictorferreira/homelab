{ lib, pkgs }:

with lib;
let
  self = {
    /* Import the YAML file and return it as a Nix object. Unfortunately, this is
       implemented as an import-from-derivation (IFD) so it will not be pretty.

       Type: importYAML :: Path -> Attrs

       Example:
       importYAML ./your-mom.yaml
       => { name = "Yor Mum"; age = 56; world = "Herown"; }
    */
    importYAML = path:
      let
        dataDrv = pkgs.runCommand "convert-yaml-to-json" { } ''
          ${getExe' pkgs.yaml2json "yaml2json"} < "${path}" > "$out"
        '';
      in
      importJSON dataDrv;

    /* Import a multi-document YAML file and return it as a Nix array. Unfortunately, this is
       implemented as an import-from-derivation (IFD) so it will not be pretty.

       Type: importMultiYAML :: Path -> Array

       Example:
       importYAML ./your-mom.yaml
       => [{ name = "Yor Mum"; age = 56; world = "Herown"; }, { ... }]
    */
    importMultiYAML = path:
      let
        dataDrv = pkgs.runCommand "yaml-to-json" { } ''
          ${pkgs.yaml2json}/bin/yaml2json < "${path}" \
            | ${pkgs.jq}/bin/jq -s 'if length==1 then .[0] else . end' \
            > "$out"
        '';
      in
      importJSON dataDrv;
  };
in
self

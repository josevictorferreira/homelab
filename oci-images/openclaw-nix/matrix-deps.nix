{ pkgs, lib, ... }:

let
  # Matrix plugin dependencies - FOD build using npm
  # Dependencies from nix-openclaw matrix extension package.json:
  # - @matrix-org/matrix-sdk-crypto-nodejs: ^0.4.0
  # - @vector-im/matrix-bot-sdk: 0.8.0-element.3
  # - markdown-it: 14.1.1
  # - music-metadata: ^11.12.1
  # - zod: ^4.3.6
  matrixPluginDeps = pkgs.buildNpmPackage {
    pname = "openclaw-matrix-plugin-deps";
    version = "1.0.0";

    src = pkgs.writeTextDir "package.json" (
      builtins.toJSON {
        name = "openclaw-matrix-plugin";
        version = "1.0.0";
        scripts = {
          build = "echo 'No build needed'";
        };
        dependencies = {
          "@matrix-org/matrix-sdk-crypto-nodejs" = "0.4.0";
          "@vector-im/matrix-bot-sdk" = "0.8.0-element.3";
          "markdown-it" = "14.1.1";
          "music-metadata" = "11.12.1";
          "zod" = "4.3.6";
        };
      }
    );

    npmDepsHash = "sha256-UviJ9mGUxwezhcaUbRcQUlYsEmzxkP1I4Bh8WGz3OzM=";

    # Copy vendored package-lock.json
    postPatch = ''
      cp ${./matrix-plugin-package-lock.json} package-lock.json
    '';

    # Don't run any build scripts, just install deps
    dontNpmBuild = false;

    # Install to a unique path to avoid merge conflicts
    installPhase = ''
      mkdir -p $out/matrix-deps
      cp -r node_modules $out/matrix-deps/
    '';
  };
in
{
  inherit matrixPluginDeps;
}

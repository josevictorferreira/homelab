{ pkgs, ... }:

let
  # Matrix plugin dependencies - FOD build using npm
  # Dependencies from upstream openclaw extensions/matrix/package.json:
  # - @matrix-org/matrix-sdk-crypto-nodejs: ^0.4.0
  # - @matrix-org/matrix-sdk-crypto-wasm: 18.1.0
  # - @sinclair/typebox: 0.34.49
  # - fake-indexeddb: ^6.2.5
  # - jiti: ^2.6.1
  # - markdown-it: 14.1.1
  # - matrix-js-sdk: 41.3.0
  # - music-metadata: ^11.12.3
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
          "@matrix-org/matrix-sdk-crypto-wasm" = "18.1.0";
          "@sinclair/typebox" = "0.34.49";
          "fake-indexeddb" = "6.2.5";
          "jiti" = "2.6.1";
          "markdown-it" = "14.1.1";
          "matrix-js-sdk" = "41.3.0";
          "music-metadata" = "11.12.3";
        };
      }
    );

    npmDepsHash = "sha256-XLyg2rVI4x7OzQaeu8RoQX141NrQoI4rNiTsDBdL+7A=";

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

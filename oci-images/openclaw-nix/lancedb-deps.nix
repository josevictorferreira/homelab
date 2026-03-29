{ pkgs, ... }:

let
  # LanceDB plugin dependencies - FOD build using npm
  # Dependencies from nix-openclaw memory-lancedb extension package.json:
  # - @lancedb/lancedb: ^0.26.2
  # - @lancedb/lancedb-linux-x64-gnu: (matched version for native binding)
  lancedbVersion = "0.26.2";

  lancedbPluginDeps = pkgs.buildNpmPackage {
    pname = "openclaw-lancedb-plugin-deps";
    version = "1.0.0";

    src = pkgs.writeTextDir "package.json" (
      builtins.toJSON {
        name = "openclaw-lancedb-plugin";
        version = "1.0.0";
        scripts = {
          build = "echo 'No build needed'";
        };
        dependencies = {
          "@lancedb/lancedb" = lancedbVersion;
          "@lancedb/lancedb-linux-x64-gnu" = lancedbVersion;
        };
      }
    );

    # Copy vendored package-lock.json
    postPatch = ''
      cp ${./lancedb-plugin-package-lock.json} package-lock.json
    '';

    npmDepsHash = "sha256-ScSlTCW4TViOSJVcw3ni2LbipB1wz+JRhfDPkvvUUx4=";
    # Install to a unique path to avoid merge conflicts
    installPhase = ''
      mkdir -p $out/lancedb-deps
      cp -r node_modules $out/lancedb-deps/
    '';
  };
in
{
  inherit lancedbPluginDeps;
}

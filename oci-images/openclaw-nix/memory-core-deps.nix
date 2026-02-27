{ pkgs, ... }:

let
  # Memory-core plugin dependencies - FOD build using npm
  # Required so `await import('sqlite-vec')` succeeds at runtime.
  # The actual .so is provided separately via extensionPath config.
  memoryCoreDeps = pkgs.buildNpmPackage {
    pname = "openclaw-memory-core-deps";
    version = "1.0.0";

    src = pkgs.writeTextDir "package.json" (
      builtins.toJSON {
        name = "openclaw-memory-core-deps";
        version = "1.0.0";
        dependencies = {
          "sqlite-vec" = "0.1.6";
        };
      }
    );

    npmDepsHash = "sha256-Q73r+VSlk80P8tLeoJyqA/CQBcVluTXLl0Fdrphetns=";

    postPatch = ''
      cp ${./memory-core-plugin-package-lock.json} package-lock.json
    '';

    dontNpmBuild = true;

    installPhase = ''
      mkdir -p $out/memory-core-deps
      cp -r node_modules $out/memory-core-deps/
    '';
  };
in
{
  inherit memoryCoreDeps;
}

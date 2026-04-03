{ pkgs, ... }:
let
  losslessClawVersion = "0.5.3";
  losslessClawPackage = pkgs.buildNpmPackage {
    pname = "openclaw-lossless-claw-plugin-deps";
    version = losslessClawVersion;
    src = pkgs.writeTextDir "package.json" (
      builtins.toJSON {
        name = "lossless-claw";
        version = losslessClawVersion;
        scripts = {
          build = "echo 'No build needed'";
        };
        dependencies = {
          "@mariozechner/pi-agent-core" = "0.64.0";
          "@mariozechner/pi-ai" = "0.64.0";
          "@sinclair/typebox" = "0.34.48";
        };
      }
    );
    # Vendored lock file
    postPatch = ''
      cp ${./lossless-claw-package-lock.json} package-lock.json
    '';
    npmDepsHash = "sha256-0azym2dn0i8gnv11519mnmw6byz06pnh8zca0y5ccf4q18lvx9bs";
    dontNpmBuild = true;
    installPhase = ''
      mkdir -p $out/lossless-claw-deps
      cp -r node_modules $out/lossless-claw-deps/
    '';
  };
in
{
  inherit losslessClawPackage;
}

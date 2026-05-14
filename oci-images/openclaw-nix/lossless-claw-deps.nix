{ pkgs, losslessClawVersion, ... }:
let
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
          "@sinclair/typebox" = "0.34.48";
          "@mariozechner/pi-agent-core" = "0.73.1";
          "@mariozechner/pi-ai" = "0.73.1";
          "@mariozechner/pi-coding-agent" = "0.73.1";
        };
      }
    );
    # Vendored lock file
    postPatch = ''
      cp ${./lossless-claw-package-lock.json} package-lock.json
    '';
    npmDepsHash = "sha256-6p1mZQSIa7y3UMxgvt01x6bqnPMt7KBDMjEF/bDJ1f8="; # Keep in sync with losslessClawInfo.npmDepsHash
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

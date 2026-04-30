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
          "@mariozechner/pi-agent-core" = "0.70.2";
          "@mariozechner/pi-ai" = "0.70.6";
          "@mariozechner/pi-coding-agent" = "0.70.6";
          "@sinclair/typebox" = "0.34.48";
        };
      }
    );
    # Vendored lock file
    postPatch = ''
      cp ${./lossless-claw-package-lock.json} package-lock.json
    '';
    npmDepsHash = "sha256-krIx9psuqvRa6mK7hk+P/uRgX/S0Gcru65wfpmgDPd0="; # Keep in sync with losslessClawInfo.npmDepsHash
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

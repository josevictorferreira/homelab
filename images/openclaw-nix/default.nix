{
  pkgs ? import <nixpkgs> { },
  inputs ? { },
  system ? "x86_64-linux",
}:
let
  dockerTools = pkgs.dockerTools;

  # Get openclaw-gateway from nix-openclaw flake input
  openclawGateway =
    inputs.nix-openclaw.packages.${system}.openclaw-gateway
      or (throw "nix-openclaw input not available");

  # Matrix plugin dependencies - pre-installed for offline support
  # These are needed for the @openclaw/matrix plugin to work without runtime npm install
  # NOTE: Disabled for smoke test due to sandbox restrictions - matrix plugin will need network for npm install
  matrixPluginDeps = pkgs.runCommand "openclaw-matrix-plugin-deps" { } ''
    mkdir -p $out/lib/openclaw/extensions/matrix
    # Create empty node_modules placeholder - matrix plugin will install deps at runtime
    mkdir -p $out/lib/openclaw/extensions/matrix/node_modules
  '';

  # Entrypoint script
  entrypointScript = pkgs.writeShellScriptBin "entrypoint.sh" (builtins.readFile ./entrypoint.sh);

  # Config template
  configTemplate = pkgs.writeTextFile {
    name = "config-template.json5";
    text = builtins.readFile ./config-template.json5;
    destination = "/etc/openclaw/config-template.json5";
  };
in
dockerTools.streamLayeredImage {
  name = "localhost/openclaw-nix";
  tag = "dev";

  contents = pkgs.buildEnv {
    name = "openclaw-rootfs";
    paths = [
      # OpenClaw gateway binary
      openclawGateway

      # Pre-installed plugin dependencies for offline support
      matrixPluginDeps

      # Core tools from toolchain
      pkgs.curl
      pkgs.jq
      pkgs.git
      pkgs.python3
      pkgs.python3Packages.requests
      pkgs.uv
      pkgs.ffmpeg
      pkgs.github-cli
      pkgs.gemini-cli
      pkgs.nodejs_22

      # Supporting packages
      pkgs.cacert
      pkgs.coreutils
      pkgs.bash
      pkgs.procps
      pkgs.tzdata

      # Entrypoint and config
      entrypointScript
      configTemplate
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/share/zoneinfo"
    ];
  };

  extraCommands = ''
    # Ensure tmp directories exist and are world-writable
    mkdir -p ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    # Create required directories for OpenClaw
    mkdir -p ./config
    mkdir -p ./state ./state/home ./state/openclaw ./state/workspace ./state/bin ./state/npm ./state/cache
    mkdir -p ./logs

    # Timezone link
    mkdir -p ./usr/share
    ln -s /share/zoneinfo ./usr/share/zoneinfo

    # Provide /usr/bin/env for shebangs
    mkdir -p ./usr/bin
    ln -s /bin/env ./usr/bin/env

    # Provide /bin/sh for scripts
    ln -s /bin/bash ./bin/sh || true

    # Copy entrypoint to root
    cp ${entrypointScript}/bin/entrypoint.sh ./entrypoint.sh
    chmod +x ./entrypoint.sh

    # Copy matrix plugin dependencies into the openclaw extensions directory
    # This allows the matrix plugin to find its dependencies without runtime npm install
    mkdir -p ./lib/openclaw/extensions/matrix
    cp -r ${matrixPluginDeps}/lib/openclaw/extensions/matrix/node_modules ./lib/openclaw/extensions/matrix/
  '';

  config = {
    Cmd = [ "/entrypoint.sh" ];
    ExposedPorts = {
      "18789/tcp" = { };
    };
    # NOTE: Do NOT set User - breaks rootless podman --user flag
    Env = [
      # OpenClaw paths
      "OPENCLAW_STATE_DIR=/state/openclaw"
      "OPENCLAW_CONFIG_PATH=/config/openclaw.json"

      # Home directory
      "HOME=/state/home"

      # Path with runtime tool directories
      "PATH=/state/bin:/state/npm/bin:/bin:/usr/bin"

      # Tool install paths
      "NPM_CONFIG_PREFIX=/state/npm"
      "NPM_CONFIG_CACHE=/state/cache/npm"

      # Cache directories
      "XDG_CACHE_HOME=/state/cache"
      "UV_CACHE_DIR=/state/cache/uv"
      "PIP_CACHE_DIR=/state/cache/pip"

      # TLS certificates
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"

      # Timezone
      "TZ=America/Sao_Paulo"
    ];
  };

  maxLayers = 120;
}

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

  # Entrypoint script source (just the text, we copy it in extraCommands)
  entrypointScriptText = builtins.readFile ./entrypoint.sh;

  # Config template - wrapped in a derivation that puts it in /etc/openclaw/
  configTemplate = pkgs.runCommand "openclaw-config-template" { } ''
    mkdir -p $out/etc/openclaw
    cat ${./config-template.json5} > $out/etc/openclaw/config-template.json5
  '';
in
dockerTools.buildImage {
  name = "localhost/openclaw-nix";
  tag = "dev";

  contents = pkgs.buildEnv {
    name = "openclaw-rootfs";
    paths = [
    configTemplate
      # OpenClaw gateway binary
      openclawGateway

      # Pre-installed plugin dependencies for offline support
      matrixPluginDeps

      # Core tools from toolchain
      pkgs.curl
      pkgs.jq
      pkgs.gnused
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

    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/share/zoneinfo"
    ];
  };

  extraCommands = ''
    # Create required directories with proper permissions
    mkdir -p ./config ./state ./logs ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    # Create entrypoint script from source text
    cat > ./entrypoint.sh << 'ENTRYPOINT_EOF'
    ${entrypointScriptText}
    ENTRYPOINT_EOF
    chmod +x ./entrypoint.sh
  '';

  config = {
    Entrypoint = [ "/bin/sh" "-c" "/entrypoint.sh" ];
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
}

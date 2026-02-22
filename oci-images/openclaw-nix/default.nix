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
    dontNpmBuild = true;

    # Install to a unique path to avoid merge conflicts
    installPhase = ''
      mkdir -p $out/matrix-deps
      cp -r node_modules $out/matrix-deps/
    '';
  };

  # Entrypoint script source (just the text, we copy it in extraCommands)
  entrypointScriptText = builtins.readFile ./entrypoint.sh;

  # OpenClaw configuration as Nix attrset, rendered to JSON at build time
  openclawConfig = import ./config.nix;
  openclawConfigJson = pkgs.writeText "openclaw-config.json" (builtins.toJSON openclawConfig);

  # Build a custom rootfs that includes openclaw + matrix deps
  # Using runCommand for full control over the file tree
  openclawRootfs = pkgs.runCommand "openclaw-rootfs" { } ''
    # Copy bin directories (ffmpeg-headless saves ~728MB closure vs full ffmpeg)
    mkdir -p $out/bin
    for pkg in ${pkgs.curl} ${pkgs.jq} ${pkgs.gnused} ${pkgs.git} ${pkgs.python3} ${pkgs.uv} ${pkgs.ffmpeg-headless} ${pkgs.github-cli} ${pkgs.gemini-cli} ${pkgs.nodejs_22} ${pkgs.procps} ${openclawGateway}; do
      if [ -d "$pkg/bin" ]; then
        cp -rsf "$pkg/bin"/* $out/bin/ 2>/dev/null || true
      fi
    done

    # Copy lib directories
    # For openclawGateway, use -rL (dereference) to create real copies, not symlinks
    # This allows us to modify the matrix extension's node_modules
    mkdir -p $out/lib
    for pkg in ${pkgs.python3} ${pkgs.nodejs_22}; do
      if [ -d "$pkg/lib" ]; then
        cp -rsf "$pkg/lib"/* $out/lib/ 2>/dev/null || true
      fi
    done
    # Copy openclawGateway lib with dereferenced symlinks (writable copies)
    if [ -d "${openclawGateway}/lib" ]; then
      cp -rL "${openclawGateway}/lib"/* $out/lib/ 2>/dev/null || true
    fi

    # Remove unused heavy optional deps (~1GB savings)
    # node-llama-cpp: optional local embeddings (we use remote via Gemini API)
    # lancedb: unused vector DB (zero references in dist/)
    # koffi: unused FFI library (zero references in dist/)
    chmod -R u+w $out/lib/openclaw/node_modules/ || true
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@node-llama-cpp+*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/node-llama-cpp@*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@lancedb+*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/lancedb@*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/koffi@*
    rm -rf $out/lib/openclaw/node_modules/node-llama-cpp
    rm -rf $out/lib/openclaw/node_modules/@node-llama-cpp
    rm -rf $out/lib/openclaw/node_modules/@lancedb
    rm -rf $out/lib/openclaw/node_modules/lancedb
    rm -rf $out/lib/openclaw/node_modules/koffi

    # Copy etc directories (except ssl certs - handled separately)
    mkdir -p $out/etc
    for pkg in ${pkgs.tzdata}; do
      if [ -d "$pkg/etc" ]; then
        cp -rsf "$pkg/etc"/* $out/etc/ 2>/dev/null || true
      fi
    done

    # Copy share/zoneinfo
    mkdir -p $out/share
    if [ -d "${pkgs.tzdata}/share/zoneinfo" ]; then
      mkdir -p $out/share/zoneinfo
      cp -rsf ${pkgs.tzdata}/share/zoneinfo/* $out/share/zoneinfo/ 2>/dev/null || true
    fi

    # Copy ssl certs from cacert
    mkdir -p $out/etc/ssl/certs
    cp -rsf ${pkgs.cacert}/etc/ssl/certs/* $out/etc/ssl/certs/ 2>/dev/null || true

    # Copy python requests
    if [ -d "${pkgs.python3Packages.requests}/lib" ]; then
      cp -rsf ${pkgs.python3Packages.requests}/lib/* $out/lib/ 2>/dev/null || true
    fi

    # Add config template (generated from Nix attrset)
    mkdir -p $out/etc/openclaw
    cp ${openclawConfigJson} $out/etc/openclaw/config-template.json

    # Fill the matrix extension's node_modules with our deps
    if [ -d "${matrixPluginDeps}/matrix-deps/node_modules" ]; then
      chmod -R u+w $out/lib/openclaw/extensions/matrix/ || true
      rm -rf $out/lib/openclaw/extensions/matrix/node_modules
      cp -r ${matrixPluginDeps}/matrix-deps/node_modules $out/lib/openclaw/extensions/matrix/
    fi
  '';
in
dockerTools.streamLayeredImage {
  name = "localhost/openclaw-nix";
  tag = "dev";

  contents = [
    openclawRootfs
    pkgs.coreutils
    pkgs.bash
  ];

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
    Entrypoint = [
      "/bin/sh"
      "-c"
      "/entrypoint.sh"
    ];
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

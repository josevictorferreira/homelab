{ pkgs
, lib
, inputs
, system
, # Version to use - change this to upgrade OpenClaw
  # Format: "YYYY.M.D" (e.g., "2026.2.23")
  # Available versions: https://github.com/openclaw/openclaw/tags
  version ? "2026.2.23"
,
}:

let
  dockerTools = pkgs.dockerTools;

  # Source info for the specified OpenClaw version
  # To update:
  #   1. Change 'version' above to the desired version
  #   2. Set both hashes to empty string: ""
  #   3. Run: nix build .#openclaw-nix-image
  #   4. Copy the correct hashes from the error message
  #   5. Update the hashes below and rebuild
  sourceInfo = {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${version}";
    hash = "sha256-TCBuoAHquGImmyiCRfJZ1flGAddQ3Uds0I3njTaif0w=";
    pnpmDepsHash = "sha256-x4uB91wUStN6ljiV1Jqx0qWK3RwAwd+5msbrlSb/sSE=";
  };

  # Build openclaw-gateway with the specified version
  # We use nix-openclaw's nixpkgs (nixos-unstable) which has fetchPnpmDeps
  openclawPkgs = inputs.nix-openclaw.inputs.nixpkgs.legacyPackages.${system};

  openclawGateway =
    openclawPkgs.callPackage (inputs.nix-openclaw + "/nix/packages/openclaw-gateway.nix")
      {
        inherit sourceInfo;
        pnpmDepsHash = sourceInfo.pnpmDepsHash;
      };

  # Import matrix plugin deps from separate file (includes scripts.build for npm)
  matrixPluginDeps = (import ./matrix-deps.nix { inherit pkgs lib; }).matrixPluginDeps;

  # Import main deps including prism-media
  prismMedia = (import ./main-deps.nix { inherit pkgs lib; }).prismMedia;

  # Native binary for matrix-sdk-crypto-nodejs (linux x64)
  matrixCryptoNative = pkgs.fetchurl {
    url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-x64-gnu.node";
    sha256 = "sha256-cHjU3ZhxKPea/RksT2IfZK3s435D8qh1bx0KnwNN5xg=";
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
    mkdir -p $out/lib
    for pkg in ${pkgs.python3} ${pkgs.nodejs_22}; do
      if [ -d "$pkg/lib" ]; then
        cp -rsf "$pkg/lib"/* $out/lib/ 2>/dev/null || true
      fi
    done
    # Copy openclawGateway lib preserving pnpm symlink structure
    # CRITICAL: use cp -a (not -rL) to preserve relative symlinks that pnpm
    # uses for correct dependency version resolution (e.g. signal-exit@3 vs @4)
    if [ -d "${openclawGateway}/lib" ]; then
      cp -a "${openclawGateway}/lib"/* $out/lib/ 2>/dev/null || true
    fi

    # Remove unused heavy optional deps (~1GB savings)
    # node-llama-cpp: optional local embeddings (we use remote via Gemini API)
    # lancedb: unused vector DB (zero references in dist/)
    chmod -R u+w $out/lib/openclaw/node_modules/ || true
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@node-llama-cpp+*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/node-llama-cpp@*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@lancedb+*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/lancedb@*
    rm -rf $out/lib/openclaw/node_modules/node-llama-cpp
    rm -rf $out/lib/openclaw/node_modules/@node-llama-cpp
    rm -rf $out/lib/openclaw/node_modules/@lancedb
    rm -rf $out/lib/openclaw/node_modules/lancedb

    cd $out/lib/openclaw

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
      cp -rL ${matrixPluginDeps}/matrix-deps/node_modules $out/lib/openclaw/extensions/matrix/
    fi

    # With cp -a, pnpm's relative symlinks are preserved and resolve correctly.
    # Only need to handle matrix extension node_modules (empty in source).
    # Make extensions dir writable so we can replace matrix node_modules
    chmod -R u+w $out/lib/openclaw/extensions/matrix/ 2>/dev/null || true

    # Fix absolute symlinks that point to the original nix store gateway path
    # cp -a preserves symlinks as-is; relative ones work but absolute ones break
    GATEWAY_STORE=$(readlink -f ${openclawGateway})
    find $out/lib/openclaw -type l 2>/dev/null | while read link; do
      tgt=$(readlink "$link")
      case "$tgt" in
        "$GATEWAY_STORE"*)
          newtgt=$(echo "$tgt" | sed "s|$GATEWAY_STORE/|$out/|")
          ln -sfn "$newtgt" "$link" 2>/dev/null || true
          ;;
      esac
    done
    echo "Fixed absolute nix store symlinks"

    # Copy native binary for matrix-sdk-crypto-nodejs
    CRYPTO_PKG="$out/lib/openclaw/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
    if [ -d "$CRYPTO_PKG" ]; then
      chmod -R u+w "$CRYPTO_PKG" || true
      cp ${matrixCryptoNative} "$CRYPTO_PKG/matrix-sdk-crypto.linux-x64-gnu.node"
      echo "Copied matrix-sdk-crypto native binary"
    fi

    # Create symlinks from original nix store paths to our copied lib
    # This ensures the gateway finds extensions at the paths it expects
    GATEWAY_STORE_PATH=$(readlink -f ${openclawGateway} | sed 's|^/nix/store/||' | cut -d'/' -f1)
    if [ -n "$GATEWAY_STORE_PATH" ]; then
      mkdir -p "$out/nix/store/$GATEWAY_STORE_PATH"
      ln -s $out/lib "$out/nix/store/$GATEWAY_STORE_PATH/lib"
    fi
  '';
in
dockerTools.streamLayeredImage {
  name = "localhost/openclaw-nix";
  tag = "v${version}";

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

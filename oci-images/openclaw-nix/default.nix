{
  pkgs,
  lib,
  inputs,
  system,
  version ? "2026.2.23",
}:

let
  dockerTools = pkgs.dockerTools;

  # Source info — change version param to upgrade
  sourceInfo = {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${version}";
    hash = "sha256-TCBuoAHquGImmyiCRfJZ1flGAddQ3Uds0I3njTaif0w=";
    pnpmDepsHash = "sha256-x4uB91wUStN6ljiV1Jqx0qWK3RwAwd+5msbrlSb/sSE=";
  };

  # Rolldown 1.0.0-rc.3 — pre-built from npm registry
  # Required for canvas:a2ui:bundle step in v2026.2.22+
  rolldownTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/rolldown/-/rolldown-1.0.0-rc.3.tgz";
    sha256 = "00h6whsmm9jwyiwqanvvmwb1g2bl2qbk650j7famcgb5zllf1zyw";
  };
  bindingTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@rolldown/binding-linux-x64-gnu/-/binding-linux-x64-gnu-1.0.0-rc.3.tgz";
    sha256 = "0xfricdk58sddqa4fslm529ppg6f0f53s4y239sgqlh98am5z63g";
  };
  oxcTypesTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@oxc-project/types/-/types-0.112.0.tgz";
    sha256 = "0qcjijc8q0gz9ghfgamkyg3nk1n7vkdffp1fnh1n9sckh5synli2";
  };
  pluginutilsTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@rolldown/pluginutils/-/pluginutils-1.0.0-rc.3.tgz";
    sha256 = "05njq25fg7qx1pmww7mqq5rwhj9f0kk6129ifydij1q2759b3pkj";
  };

  rolldown = pkgs.stdenv.mkDerivation {
    pname = "rolldown";
    version = "1.0.0-rc.3";
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = [ pkgs.nodejs_22 ];

    installPhase = ''
      # Assemble node_modules tree from pre-built npm tarballs
      mkdir -p $out/lib/node_modules/rolldown/node_modules/{@rolldown/binding-linux-x64-gnu,@oxc-project/types,@rolldown/pluginutils}

      tar xzf ${rolldownTgz} -C $out/lib/node_modules/rolldown --strip-components=1
      tar xzf ${bindingTgz} -C $out/lib/node_modules/rolldown/node_modules/@rolldown/binding-linux-x64-gnu --strip-components=1
      tar xzf ${oxcTypesTgz} -C $out/lib/node_modules/rolldown/node_modules/@oxc-project/types --strip-components=1
      tar xzf ${pluginutilsTgz} -C $out/lib/node_modules/rolldown/node_modules/@rolldown/pluginutils --strip-components=1

      # Create wrapper that invokes cli.mjs with node
      mkdir -p $out/bin
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/rolldown \
        --add-flags "$out/lib/node_modules/rolldown/bin/cli.mjs" \
        --set NODE_PATH "$out/lib/node_modules"
    '';
  };

  # Get overlay and pkgs from nix-openclaw
  openclawOverlay = import (inputs.nix-openclaw + "/nix/overlay.nix");
  openclawPkgs = import inputs.nix-openclaw.inputs.nixpkgs {
    inherit system;
    overlays = [ openclawOverlay ];
  };

  # Override gateway: custom source + rolldown in PATH
  openclawGateway =
    (openclawPkgs.openclaw-gateway.override {
      inherit sourceInfo;
      pnpmDepsHash = sourceInfo.pnpmDepsHash;
    }).overrideAttrs
      (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ rolldown ];
      });

  matrixPluginDeps = (import ./matrix-deps.nix { inherit pkgs lib; }).matrixPluginDeps;
  prismMedia = (import ./main-deps.nix { inherit pkgs lib; }).prismMedia;
  matrixCryptoNative = pkgs.fetchurl {
    url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-x64-gnu.node";
    sha256 = "sha256-cHjU3ZhxKPea/RksT2IfZK3s435D8qh1bx0KnwNN5xg=";
  };
  entrypointScriptText = builtins.readFile ./entrypoint.sh;
  openclawConfig = import ./config.nix;
  openclawConfigJson = pkgs.writeText "openclaw-config.json" (builtins.toJSON openclawConfig);

  openclawRootfs = pkgs.runCommand "openclaw-rootfs" { } ''
    mkdir -p $out/bin
    for pkg in ${pkgs.curl} ${pkgs.jq} ${pkgs.gnused} ${pkgs.git} ${pkgs.python3} ${pkgs.uv} ${pkgs.ffmpeg-headless} ${pkgs.github-cli} ${pkgs.gemini-cli} ${pkgs.nodejs_22} ${pkgs.procps} ${openclawGateway}; do
      if [ -d "$pkg/bin" ]; then cp -rsf "$pkg/bin"/* $out/bin/ 2>/dev/null || true; fi
    done
    mkdir -p $out/lib
    for pkg in ${pkgs.python3} ${pkgs.nodejs_22}; do
      if [ -d "$pkg/lib" ]; then cp -rsf "$pkg/lib"/* $out/lib/ 2>/dev/null || true; fi
    done
    if [ -d "${openclawGateway}/lib" ]; then cp -a "${openclawGateway}/lib"/* $out/lib/ 2>/dev/null || true; fi
    chmod -R u+w $out/lib/openclaw/node_modules/ || true
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@node-llama-cpp+* $out/lib/openclaw/node_modules/.pnpm/node-llama-cpp@*
    rm -rf $out/lib/openclaw/node_modules/.pnpm/@lancedb+* $out/lib/openclaw/node_modules/.pnpm/lancedb@*
    rm -rf $out/lib/openclaw/node_modules/node-llama-cpp $out/lib/openclaw/node_modules/@node-llama-cpp
    rm -rf $out/lib/openclaw/node_modules/@lancedb $out/lib/openclaw/node_modules/lancedb
    cd $out/lib/openclaw
    mkdir -p $out/etc
    for pkg in ${pkgs.tzdata}; do
      if [ -d "$pkg/etc" ]; then cp -rsf "$pkg/etc"/* $out/etc/ 2>/dev/null || true; fi
    done
    mkdir -p $out/share/zoneinfo
    cp -rsf ${pkgs.tzdata}/share/zoneinfo/* $out/share/zoneinfo/ 2>/dev/null || true
    mkdir -p $out/etc/ssl/certs
    cp -rsf ${pkgs.cacert}/etc/ssl/certs/* $out/etc/ssl/certs/ 2>/dev/null || true
    if [ -d "${pkgs.python3Packages.requests}/lib" ]; then cp -rsf ${pkgs.python3Packages.requests}/lib/* $out/lib/ 2>/dev/null || true; fi
    mkdir -p $out/etc/openclaw
    cp ${openclawConfigJson} $out/etc/openclaw/config-template.json
    if [ -d "${matrixPluginDeps}/matrix-deps/node_modules" ]; then
      chmod -R u+w $out/lib/openclaw/extensions/matrix/ || true
      rm -rf $out/lib/openclaw/extensions/matrix/node_modules
      cp -rL ${matrixPluginDeps}/matrix-deps/node_modules $out/lib/openclaw/extensions/matrix/
    fi
    chmod -R u+w $out/lib/openclaw/extensions/matrix/ 2>/dev/null || true
    GATEWAY_STORE=$(readlink -f ${openclawGateway})
    find $out/lib/openclaw -type l 2>/dev/null | while read link; do
      tgt=$(readlink "$link")
      case "$tgt" in "$GATEWAY_STORE"*) ln -sfn "$(echo "$tgt" | sed "s|$GATEWAY_STORE/|$out/|")" "$link" 2>/dev/null || true ;; esac
    done
    CRYPTO_PKG="$out/lib/openclaw/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
    if [ -d "$CRYPTO_PKG" ]; then chmod -R u+w "$CRYPTO_PKG" || true; cp ${matrixCryptoNative} "$CRYPTO_PKG/matrix-sdk-crypto.linux-x64-gnu.node"; fi
    GATEWAY_STORE_PATH=$(readlink -f ${openclawGateway} | sed 's|^/nix/store/||' | cut -d'/' -f1)
    if [ -n "$GATEWAY_STORE_PATH" ]; then mkdir -p "$out/nix/store/$GATEWAY_STORE_PATH"; ln -s $out/lib "$out/nix/store/$GATEWAY_STORE_PATH/lib"; fi
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
    mkdir -p ./config ./state ./logs ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp
    cat > ./entrypoint.sh << 'EOF'
    ${entrypointScriptText}
    EOF
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
    Env = [
      "OPENCLAW_STATE_DIR=/state/openclaw"
      "OPENCLAW_CONFIG_PATH=/config/openclaw.json"
      "HOME=/state/home"
      "PATH=/state/bin:/state/npm/bin:/bin:/usr/bin"
      "NPM_CONFIG_PREFIX=/state/npm"
      "NPM_CONFIG_CACHE=/state/cache/npm"
      "XDG_CACHE_HOME=/state/cache"
      "UV_CACHE_DIR=/state/cache/uv"
      "PIP_CACHE_DIR=/state/cache/pip"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "TZ=America/Sao_Paulo"
    ];
  };
}

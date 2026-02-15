{
  pkgs ? import <nixpkgs> { },
}:
let
  # Pull the official OpenClaw image as base
  # Retrieved using: nix-prefetch-docker ghcr.io/openclaw/openclaw --arch amd64 --os linux
  openclawImage = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/openclaw/openclaw";
    imageDigest = "sha256:7503c7dc56800b61f1223d3c4032ada61a100538a41425210b4043b71f871488";
    sha256 = "sha256-PF5i7dwr9/jW21elpttqUe/Pe6STCCJ2RN2nbI8Kq1A=";
    os = "linux";
    arch = "amd64";
  };

  # Node.js environment (includes npm)
  nodeEnv = pkgs.buildEnv {
    name = "openclaw-node-env";
    paths = with pkgs; [
      nodejs_20
    ];
  };
in
pkgs.dockerTools.buildImage {
  name = "ghcr.io/josevictorferreira/openclaw-matrix";
  tag = "latest";

  fromImage = openclawImage;

  copyToRoot = pkgs.buildEnv {
    name = "openclaw-rootfs";
    paths = [
      nodeEnv
      pkgs.cacert
      pkgs.uv
    ];
    pathsToLink = [ "/bin" ];
  };

  extraCommands = ''
    # Ensure /home/node/.openclaw exists and is writable
    mkdir -p ./home/node/.openclaw
    chown -R 1000:1000 ./home/node/.openclaw
    chmod 755 ./home/node/.openclaw

    # Ensure tmp directories exist and are world-writable
    mkdir -p ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    # Create a global node_modules directory for the matrix-sdk
    mkdir -p ./opt/node-global

    # Create wrapper script to install matrix-bot-sdk at runtime if needed
    # or we could install it here during build
  '';

  runAsRoot = ''
    #!/bin/sh
    ${pkgs.dockerTools.shadowSetup}

    # Create node user if it doesn't exist
    useradd -u 1000 -m node 2>/dev/null || true

    # Install matrix-bot-sdk globally in the container
    export HOME=/home/node
    export NPM_CONFIG_PREFIX=/opt/node-global
    export PATH="/opt/node-global/bin:$PATH"

    # Install @google/gemini-cli globally so it's available as a binary
    npm install -g @google/gemini-cli

    # Switch to node user context for npm install
    su - node -c "
      mkdir -p ~/.openclaw/plugins/node_modules
      cd ~/.openclaw/plugins
      npm init -y
      npm install @vector-im/matrix-bot-sdk
    "

    # Make the directory accessible
    chown -R node:node /home/node/.openclaw
    chmod -R 755 /home/node/.openclaw
  '';

  config = {
    User = "node";
    WorkingDir = "/home/node";
    Env = [
      "HOME=/home/node"
      "NODE_PATH=/home/node/.openclaw/plugins/node_modules:/opt/node-global/lib/node_modules"
      "PATH=/opt/node-global/bin:/usr/local/bin:/usr/bin:/bin"
    ];
    Cmd = [
      "npx"
      "openclaw"
      "gateway"
    ];
    ExposedPorts = {
      "18789/tcp" = { };
    };
  };
}

{
  pkgs ? import <nixpkgs> { },
  host ? "0.0.0.0",
  port ? 8000,
  tz ? "America/Sao_Paulo",
}:
let
  dockerTools = pkgs.dockerTools;
  mcpoConfig = {
    mcpServers = {
      memory = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-memory"
        ];
      };
      sequential-thinking = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-sequential-thinking"
        ];
      };
      searxng = {
        command = "npx";
        args = [
          "-y"
          "mcp-searxng"
        ];
        env = {
          SEARXNG_URL = "http://10.10.10.125";
        };
      };
    };
  };
  configJson = builtins.toJSON mcpoConfig;
  configFile = pkgs.writeTextFile {
    name = "mcpo-config.json";
    text = configJson;
    destination = "/etc/mcpo/config.json";
  };
in
dockerTools.buildImage {
  name = "mcpo";
  tag = "latest";
  copyToRoot = pkgs.buildEnv {
    name = "rootfs";
    paths = [
      pkgs.uv
      pkgs.python311
      pkgs.cacert
      pkgs.tzdata
      pkgs.coreutils
      pkgs.procps
      pkgs.nodejs_20
      pkgs.bash # add a shell
      configFile
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/share/zoneinfo"
    ];
  };
  extraCommands = ''
    # App dir
    mkdir -p ./app

    # Timezone link
    mkdir -p ./usr/share
    ln -s /share/zoneinfo ./usr/share/zoneinfo

    # Ensure tmp exists and is world-writable
    mkdir -p ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    # Provide /usr/bin/env for shebangs
    mkdir -p ./usr/bin
    ln -s /bin/env ./usr/bin/env

    # Provide /usr/bin/python[3] for shebangs that expect it
    ln -s /bin/python3 ./usr/bin/python3 || true
    ln -s /bin/python3 ./usr/bin/python || true

    # Provide /bin/sh (some launchers rely on it)
    ln -s /bin/bash ./bin/sh || true

    # Ensure root home exists (some tools use $HOME)
    mkdir -p ./root

    # Optional: a cache for uv to reduce /tmp usage
    mkdir -p ./var/cache/uv
  '';
  config = {
    WorkingDir = "/app";
    Env = [
      "UV_SYSTEM_PYTHON=1"
      "PATH=/bin:/usr/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "TZ=${tz}"
      "TMPDIR=/tmp"
      "HOME=/root"
      "XDG_CACHE_HOME=/var/cache"
      "UV_CACHE_DIR=/var/cache/uv"
    ];
    ExposedPorts = {
      "${toString port}/tcp" = { };
    };
    Cmd = [
      "uvx"
      "mcpo"
      "--host"
      host
      "--port"
      (toString port)
      "--config"
      "/etc/mcpo/config.json"
      "--hot-reload"
    ];
  };
}

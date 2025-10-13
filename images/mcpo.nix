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
      configFile
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/share/zoneinfo"
    ];
  };

  extraCommands = ''
    mkdir -p ./app
    mkdir -p ./usr/share
    ln -s /share/zoneinfo ./usr/share/zoneinfo
  '';

  config = {
    WorkingDir = "/app";
    Env = [
      "UV_SYSTEM_PYTHON=1"
      "PATH=/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "TZ=${tz}"
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

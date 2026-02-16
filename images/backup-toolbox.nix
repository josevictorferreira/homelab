{
  pkgs ? import <nixpkgs> { },
}:
let
  dockerTools = pkgs.dockerTools;
  postgresql = pkgs.postgresql_18;
in
dockerTools.buildImage {
  name = "ghcr.io/josevictorferreira/backup-toolbox";
  tag = "1.0.0";

  copyToRoot = pkgs.buildEnv {
    name = "rootfs";
    paths = [
      postgresql # pg_dumpall, psql
      pkgs.zstd
      pkgs.minio-client # mc
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert # CA certs for HTTPS
      pkgs.gnugrep
      pkgs.getent # needed by mc for home dir resolution
      pkgs.jq # JSON parsing for mc output
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/share"
    ];
  };

  extraCommands = ''
    mkdir -p tmp
    chmod 1777 tmp
  '';

  config = {
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PATH=/bin"
      "HOME=/tmp" # mc needs HOME for config dir
    ];
    WorkingDir = "/tmp";
    Cmd = [ "/bin/bash" ];
  };
}

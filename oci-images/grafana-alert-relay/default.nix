{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:
let
  inherit (pkgs) dockerTools;
in
dockerTools.buildImage {
  name = "ghcr.io/josevictorferreira/grafana-alert-relay";
  tag = "1.0.1";

  copyToRoot = pkgs.buildEnv {
    name = "rootfs";
    paths = [
      (pkgs.buildGoModule {
        pname = "grafana-alert-relay";
        version = "1.0.0";
        src = ./.;
        vendorHash = null;
        subpackages = [ "." ];
        ldflags = [
          "-s"
          "-w"
        ];
      })
      pkgs.cacert
    ];
    pathsToLink = [ "/bin" ];
  };

  extraCommands = ''
    mkdir -p tmp
    chmod 1777 tmp
  '';

  config = {
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PATH=/bin"
    ];
    WorkingDir = "/tmp";
    Cmd = [ "/bin/grafana-alert-relay" ];
    ExposedPorts = {
      "8080/tcp" = { };
    };
  };
}

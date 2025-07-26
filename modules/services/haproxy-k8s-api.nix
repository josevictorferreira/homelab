{ lib, ... }:

let
  config = import ./../../shared/cluster-config.nix;

  masters = builtins.map
    (name:
      let
        host = config.hosts.${name};
      in
      "${name} ${host.ipAddress}:6443"
    )
    config.masters;
in
{
  services.haproxy = {
    enable = true;

    config = ''
      global
        log stdout format raw local0
        maxconn 4000

      defaults
        mode tcp
        log global
        option tcplog
        timeout connect 5s
        timeout client 50s
        timeout server 50s

      frontend kubernetes-api
        bind *:6443
        default_backend kubernetes-masters

      backend kubernetes-masters
        balance roundrobin
        option tcp-check
    '' + (lib.concatStringsSep "\n"
      (map (s: "        server ${s} check") masters)) + "\n";
  };
}

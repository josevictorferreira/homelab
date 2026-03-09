{ lib, homelab, ... }:

let
  controlPlanes = builtins.map
    (name:
      let
        host = homelab.nodes.hosts.${name};
      in
      "${name} ${host.ipAddress}:6444"
    )
    homelab.nodes.group."k8s-control-plane".names;
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
        timeout connect 10s
        timeout client 3600s
        timeout server 3600s
        timeout tunnel 86400s

      frontend kubernetes-api
        bind *:6443
        default_backend kubernetes-masters

      backend kubernetes-masters
        balance roundrobin
        option tcp-check
    '' + (lib.concatStringsSep "\n"
      (map (s: "        server ${s} check") controlPlanes)) + "\n";
  };
}

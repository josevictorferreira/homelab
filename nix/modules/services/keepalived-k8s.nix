{ lib, ... }:

let
  config = import ./../../shared/cluster-config.nix;
  isMaster = config.networking.hostName == builtins.head (config.masters);
in
{
  services.keepalived = {
    enable = true;
    openFirewall = true;

    vrrpInstances."k8s-api" = {
      interface = "eth0";
      virtualRouterId = 51;
      state = lib.mkDefault (if isMaster then "MASTER" else "BACKUP");
      priority = lib.mkDefault (if isMaster then 150 else 100);
      advertInt = 1;
      virtualIps = [ "${config.clusterIpAddress}/24 dev eth0" ];

      trackScripts = [ "haproxy-up" ];
    };

    vrrpScripts."haproxy-up" = {
      script = "systemctl is-active --quiet haproxy";
      interval = 2;
      rise = 2;
      fall = 2;
    };
  };
}

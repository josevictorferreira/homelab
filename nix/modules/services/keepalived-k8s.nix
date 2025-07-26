{ lib, hostName, hostConfig, clusterConfig, ... }:

let
  isMaster = hostName == builtins.head (clusterConfig.masters);
in
{
  services.keepalived = {
    enable = true;
    openFirewall = true;

    vrrpInstances."k8s-api" = {
      interface = hostConfig.interface;
      virtualRouterId = 51;
      state = lib.mkDefault (if isMaster then "MASTER" else "BACKUP");
      priority = lib.mkDefault (if isMaster then 150 else 100);
      virtualIps = [{ addr = "${clusterConfig.clusterIpAddress}/24"; dev = hostConfig.interface; }];
      trackScripts = [ "haproxy-up" ];
    };

    vrrpScripts."haproxy-up" = {
      script = "systemctl is-active --quiet haproxy";
      interval = 2;
      rise = 2;
      fall = 2;
      user = "root";
    };
  };
}

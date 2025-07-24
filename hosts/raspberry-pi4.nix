{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
    ./../modules/roles/nfs-server.nix
    ./../modules/services/wake-on-lan-observer.nix
  ];

  networking.hostName = "raspberry-pi4";
  networking.staticIP = {
    enable = true;
    interface = "end0";
    address = hostConfig.ipAddress;
  };
}

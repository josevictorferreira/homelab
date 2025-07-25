{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
  ];

  networking.hostName = hostName;
  networking.staticIP = {
    enable = false;
    interface = "ens18";
    address = hostConfig.ipAddress;
  };
  networking.useDHCP = true;
}

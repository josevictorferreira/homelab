{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
  ];

  networking.hostName = hostName;
  networking.staticIP = {
    enable = true;
    interface = "ens18";
    address = hostConfig.ipAddress;
  };
}

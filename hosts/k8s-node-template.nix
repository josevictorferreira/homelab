{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
  ];

  networking.hostName = hostName;
  networking.useDHCP = true;
  networking.staticIP = {
    enable = false;
    interface = "ens18";
  };
}

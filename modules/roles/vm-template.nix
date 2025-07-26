{ lib, hostConfig, ... }:

{
  networking.useDHCP = lib.mkForce true;
  networking.staticIP = {
    enable = lib.mkForce false;
    interface = lib.mkForce hostConfig.interface;
  };
}

{ config, lib, pkgs, ... }:

{
  options.networking.staticIP = {
    enable = lib.mkEnableOption "static IP configuration";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Network interface name";
    };

    address = lib.mkOption {
      type = lib.types.str;
      description = "IP address";
    };

    prefixLength = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Network prefix length";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.1";
      description = "Default gateway";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "DNS nameservers";
    };
  };

  config = lib.mkIf config.networking.staticIP.enable {
    networking.interfaces.${config.networking.staticIP.interface} = {
      ipv4.addresses = [{
        address = config.networking.staticIP.address;
        prefixLength = config.networking.staticIP.prefixLength;
      }];
      useDHCP = false;
    };
    networking.defaultGateway = {
      address = config.networking.staticIP.gateway;
      interface = config.networking.staticIP.interface;
    };
    networking.useDHCP = false;
    networking.nameservers = config.networking.staticIP.nameservers;
    networking.firewall.enable = true;
  };
}

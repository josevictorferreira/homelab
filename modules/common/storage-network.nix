{ config, lib, ... }:

# Dedicated 2.5 GbE storage link (USB adapter on an isolated switch) carrying
# the Ceph cluster network. The adapter is renamed by MAC so its name survives
# moving it between USB ports, and its address is re-applied whenever it
# re-enumerates (r8152 adapters reset under load).
let
  cfg = config.networking.storageNetwork;
  interface = "storage0";
in
{
  options.networking.storageNetwork = {
    enable = lib.mkEnableOption "the dedicated storage network interface";

    mac = lib.mkOption {
      type = lib.types.str;
      description = "MAC address of the storage network adapter";
    };

    address = lib.mkOption {
      type = lib.types.str;
      description = "IP address on the storage network";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.network.links."10-${interface}" = {
      matchConfig.MACAddress = cfg.mac;
      linkConfig.Name = interface;
    };

    networking.interfaces.${interface} = {
      ipv4.addresses = [{
        inherit (cfg) address;
        prefixLength = 24;
      }];
      useDHCP = false;
    };

    # The stock unit is only wanted by network.target, so it never comes back
    # after the adapter drops off the USB bus and reappears.
    systemd.services."network-addresses-${interface}".wantedBy =
      [ "sys-subsystem-net-devices-${interface}.device" ];
  };
}

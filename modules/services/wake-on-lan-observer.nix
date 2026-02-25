{ lib, config, pkgs, ... }:

let
  cfg = config.services.wakeOnLanObserver;
  mkWolService = node: {
    "pve-wol-${node.name}" = {
      description = "Check if ${node.name} is online and send WoL if down";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "pve-wol-${node.name}" ''
          if ! ${pkgs.iputils}/bin/ping -c 2 -w 3 ${node.ipAddress} > /dev/null; then
              echo "${node.name} is offline. Sending WoL..."
              ${pkgs.wakeonlan}/bin/wakeonlan ${node.mac}
          else
              echo "${node.name} is online."
          fi
        '';
      };
    };
  };
  mkWolTimer = node: {
    "pve-wol-${node.name}" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
    };
  };
in
{
  options.services.wakeOnLanObserver = {
    enable = lib.mkEnableOption "Enable Wake-on-LAN observer service";
    machines = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "List of machines to monitor for Wake-on-LAN. Each machine should have a name, IP address, and MAC address.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.iputils
      pkgs.wakeonlan
    ];

    systemd.services = lib.foldl (acc: node: acc // mkWolService node) { } cfg.machines;
    systemd.timers = lib.foldl (acc: node: acc // mkWolTimer node) { } cfg.machines;
  };
}

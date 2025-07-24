{ config, pkgs, lib, ... }:

let
    pveNodes = [
        { name = "pve1"; ip = "10.10.10.200"; mac = "68:1D:EF:30:C1:03"; }
        { name = "pve2"; ip = "10.10.10.201"; mac = "68:1D:EF:3B:71:4E"; }
        { name = "pve3"; ip = "10.10.10.202"; mac = "68:1D:EF:3E:30:37"; }
        { name = "pve4"; ip = "10.10.10.203"; mac = "B0:41:6F:16:1F:72"; }
    ];

    mkPveService = node: {
        "pve-wol-${node.name}" = {
            description = "Check if ${node.name} is online and send WoL if down";
            wantedBy = [ "default.target" ];
            serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "pve-wol-${node.name}" ''
                    if ! ${pkgs.iputils}/bin/ping -c 2 -w 3 ${node.ip} > /dev/null; then
                        echo "${node.name} is offline. Sending WoL..."
                        ${pkgs.wakeonlan}/bin/wakeonlan ${node.mac}
                    else
                        echo "${node.name} is online."
                    fi
                '';
            };
        };

    };

    mkPveTimer = node: {
        "pve-wol-${node.name}" = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
                OnUnitActiveSec = "5min";
                Persistent = true;
            };
        };
    };

    allServices = lib.foldl (acc: node: acc // mkPveService node) {} pveNodes;
    allTimers = lib.foldl (acc: node: acc // mkPveTimer node) {} pveNodes;
in
{
    environment.systemPackages = [
        pkgs.iputils
        pkgs.wakeonlan
    ];

    systemd.services = allServices;
    systemd.timers = allTimers;
}

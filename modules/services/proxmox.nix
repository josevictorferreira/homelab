{ pkgs, lib, proxmox-nixos, ... }:

{
    services.proxmox-ve = {
        enable = true;
        ipAddress = "10.10.10.209";
    };

    nixpkgs.overlays = [
        proxmox-nixos.overlays.${system}
    ];
}

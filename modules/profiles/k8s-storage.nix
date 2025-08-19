{ lib, config, pkgs, homelab, ... }:

let
  cfg = config.profiles."k8s-storage";
in
{
  options.profiles."k8s-storage" = {
    enable = lib.mkEnableOption "Enable the node to be a Kubernetes storage node";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ceph
      ceph-client
      util-linux
      parted
      gptfdisk
      lvm2
    ];

    boot.kernelModules = [
      "ceph"
      "rbd"
      "nfs"
    ];

    systemd.services.containerd.serviceConfig = {
      LimitNOFILE = lib.mkForce null;
    };
  };
}

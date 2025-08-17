{ lib, config, pkgs, ... }:

let
  cfg = config.roles.k8sStorage;
in
{
  options.roles.k8sStorage = {
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

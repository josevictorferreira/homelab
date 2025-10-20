{
  lib,
  config,
  ...
}:

let
  cfg = config.profiles."amd-gpu";
  pkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
      rocmSupport = true;
    };
  };
in
{
  options.profiles."amd-gpu" = {
    enable = lib.mkEnableOption "Enable amd gpu configurations to the node";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}" ];
    hardware.cpu.amd.updateMicrocode = true;

    hardware.graphics = {
      enable = true;
      extraPackages = [
        pkgs.libva
        pkgs.libva-utils
        pkgs.rocmPackages.clr
        pkgs.rocmPackages.clr.icd
        pkgs.rocmPackages.rocmPath
        pkgs.rocmPackages.rocminfo
        pkgs.rocmPackages.rocm-smi
        pkgs.rocmPackages.rocm-runtime
      ];
      enable32Bit = true;
    };

    hardware.amdgpu.amdvlk = {
      enable = true;
      support32Bit.enable = true;
    };

    environment.systemPackages = [
      pkgs.pciutils
      pkgs.vulkan-tools
      pkgs.clinfo
    ];

    environment.variables = {
      PATH = [ "/opt/rocm/bin" ];
      LD_LIBRARY_PATH = [
        "/opt/rocm/lib"
        "/run/opengl-driver/lib"
      ];
      ROCM_PATH = "/opt/rocm";
    };
  };
}

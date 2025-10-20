{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.profiles."amd-gpu";
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
      extraPackages = with pkgs; [
        amdvlk
        libva
        libva-utils
        rocmPackages.clr
        rocmPackages.clr.icd
        rocmPackages.rocmPath
        rocmPackages.rocminfo
        rocmPackages.rocm-smi
        rocmPackages.rocm-runtime
      ];
      enable32Bit = true;
      extraPackages32 = with pkgs; [
        driversi686Linux.amdvlk
      ];
    };

    hardware.amdgpu.amdvlk = {
      enable = true;
      support32Bit.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pciutils
      vulkan-tools
      clinfo
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

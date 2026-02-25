{ lib
, config
, pkgs
, ...
}:
let
  cfg = config.profiles."amd-gpu";
in
{
  options.profiles."amd-gpu" = {
    enable = lib.mkEnableOption "Enable amd gpu configurations to the node";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "amdgpu.sg_display=0" ];

    systemd.tmpfiles.rules = [ "L+    /opt/rocm   -    -    -     -    ${pkgs.rocmPackages.clr}" ];

    hardware = {
      cpu.amd.updateMicrocode = true;

      graphics = {
        enable = true;
        extraPackages = [
          pkgs.clinfo
          pkgs.rocmPackages.rocminfo
          pkgs.rocmPackages.rocm-device-libs
          pkgs.rocmPackages.rocm-runtime
        ];
        enable32Bit = true;
      };

      amdgpu.amdvlk = {
        enable = true;
        support32Bit.enable = true;
      };
    };

    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.rocmSupport = "rocm";

    virtualisation.containerd.enable = true;

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

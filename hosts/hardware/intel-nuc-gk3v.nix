{ config, lib, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot = {
    supportedFilesystems = [ "zfs" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
      kernelModules = [ ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = "rpool/root";
      fsType = "zfs";
    };

    "/nix" = {
      device = "rpool/nix";
      fsType = "zfs";
    };

    "/var/log" = {
      device = "rpool/log";
      fsType = "zfs";
    };

    "/boot" = {
      device = "/dev/disk/by-partlabel/EFI";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
  };

  swapDevices = [ ];

  # A spurious ACPI GPE on this board fires phantom short power-button presses
  # (PNP0C0C), which logind acts on and cleanly powers the host off in a loop.
  # Ignore short presses; a deliberate long press still powers off.
  services.logind = {
    powerKey = "ignore";
    powerKeyLongPress = "poweroff";
  };

  # Both gk3v units sit at Tjmax (101-105C) with millions of package throttle
  # events, and gamma hard-resets under load (journal ends mid-line, no
  # shutdown, bootstatus=0). The Celeron N5105 is Jasper Lake, so undervolting
  # is not an option: there are no MSR 0x150 voltage offsets on Atom cores.
  # Capping sustained package power is what is left, and it cut throttle events
  # from thousands per 30s to ~40 while raising sustained clocks.
  #
  # MITIGATION ONLY: a 6W-TDP-capped part still reading 101C means the heat is
  # not leaving the die. The heatsink/fan needs physical cleaning + repaste;
  # no kernel setting can substitute for that.
  systemd.services.gk3v-power-cap = {
    description = "Cap Celeron N5105 package power (thermal mitigation)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rapl=/sys/class/powercap/intel-rapl:0
      if [ -d "$rapl" ]; then
        # PL1 sustained 6W, PL2 burst 8W (stock is 10W/15W).
        echo 6000000 > "$rapl/constraint_0_power_limit_uw" || true
        echo 8000000 > "$rapl/constraint_1_power_limit_uw" || true
      fi
      # Turbo to 2.9GHz is the sharpest heat spike on a dead cooler.
      if [ -w /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
      fi
    '';
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

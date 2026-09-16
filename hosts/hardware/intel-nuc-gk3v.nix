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

  # Thermal mitigation for a gk3v whose cooler is not transferring heat: the
  # Celeron N5105 pins at Tjmax (101-105C) with millions of package throttle
  # events, which starves kubelet enough that pods stop starting, and the board
  # hard-resets under load (journal ends mid-line, no shutdown, bootstatus=0).
  # Undervolting is not an option on Jasper Lake: no MSR 0x150 voltage offsets
  # on Atom cores. Capping sustained package power is what is left; measured it
  # cut throttle events from thousands per 30s to ~40 and raised sustained
  # clocks.
  #
  # Scoped to lab-alpha-cp because only that unit still has the fault. After
  # gamma's heatsink was cleaned/repasted it runs 63C at stock 10W/15W with
  # turbo on and ZERO throttle events, so capping it would only slow a healthy
  # node. Drop this block once alpha gets the same service - a cap is a
  # workaround for bad cooling, not a substitute for fixing it.
  # 2026-09-15: gamma's cooler failed again (104 C at boot, hard-reset loop),
  # so the cap applies to every gk3v host until both are physically serviced.
  # 2026-09-16: gamma hard-resets under load even at 6 W (two resets in seven
  # minutes while Ceph was recovering), so it gets a tighter cap than alpha,
  # which runs etcd and cannot afford 1.2 GHz.
  systemd.services = let
    gamma = config.networking.hostName == "lab-gamma-wk";
    pl1 = if gamma then "4000000" else "6000000";
    pl2 = if gamma then "6000000" else "8000000";
    maxKhz = if gamma then "1200000" else "1500000";
  in {
    gk3v-power-cap = {
      description = "Cap Celeron N5105 package power (thermal mitigation)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        rapl=/sys/class/powercap/intel-rapl:0
        if [ -d "$rapl" ]; then
          # PL1 sustained / PL2 burst (stock is 10W/15W).
          echo ${pl1} > "$rapl/constraint_0_power_limit_uw" || true
          echo ${pl2} > "$rapl/constraint_1_power_limit_uw" || true
        fi
        # Turbo to 2.9GHz is the sharpest heat spike on a dead cooler.
        if [ -w /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
          echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
        fi
        # Clamp clocks well below the 2.9GHz max; heat, not throughput, is the limit.
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
          echo ${maxKhz} > "$f" || true
        done
      '';
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

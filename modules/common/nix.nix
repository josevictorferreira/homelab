{ lib, config, ... }:

let
  cfg = config.nixDefaults;
in
{
  options.nixDefaults = {
    enable = lib.mkEnableOption "Enable Nix package manager";
  };

  config = lib.mkIf cfg.enable {
    system.stateVersion = "25.05";

    nix.settings.trusted-users = [ "root" "@wheel" ];
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Self-hosted Attic binary cache (see nix_homelab_plan.md).
    nix.settings.extra-substituters = [ "http://10.10.10.161:8080/homelab" ];
    # Trusted public key for the homelab attic cache (from `attic cache info homelab`).
    nix.settings.extra-trusted-public-keys = [ "homelab:6mcMiciTmo9ql8grx9u5ldKLsoscq3zS4KUQ6V6mVy8=" ];
    # Don't hang deploys when the cache is down.
    nix.settings.connect-timeout = 5;
    nix.settings.builders-use-substitutes = true;
  };
} 

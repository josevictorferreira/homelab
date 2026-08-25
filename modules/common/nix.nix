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
    # Substituter is safe to add now (untrusted caches fall through); the
    # public key is filled in after Phase 2 creates the `homelab` cache
    # (`attic cache info homelab`). Keep cache.nixos.org primary via extra-*.
    nix.settings.extra-substituters = [ "http://10.10.10.161:8080/homelab" ];
    # TODO(phase-2): insert "homelab:<public-key>" once the cache exists.
    nix.settings.extra-trusted-public-keys = [ ];
    # Don't hang deploys when the cache is down.
    nix.settings.connect-timeout = 5;
    nix.settings.builders-use-substitutes = true;
  };
} 

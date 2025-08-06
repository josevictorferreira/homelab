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
  };
} 

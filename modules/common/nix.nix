{ lib, config, ... }:

let
  cfg = config.nixDefaults;
in
{
  options.nixDefaults = {
    enable = lib.mkEnableOption "Enable Nix package manager";
  };

  config = lib.mkIf cfg.enable {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    system.stateVersion = "25.05";
  };
} 

{ lib, config, ... }:

let
  cfg = config.profiles."tailscale-router";
in
{
  options.profiles."tailscale-router" = {
    enable = lib.mkEnableOption "Tailscale subnet router role marker";
  };

  # This is a marker profile - actual tailscale configuration is in tailscale.nix
  # The tailscale-router role is detected by the tailscale.nix profile to enable
  # subnet routing features (--advertise-routes, useRoutingFeatures = "server")
  config = lib.mkIf cfg.enable {
    # No additional configuration needed - handled by tailscale.nix
  };
}

{
  lib,
  config,
  hostConfig,
  ...
}:

let
  cfg = config.profiles.tailscale;
  isRouter = builtins.elem "tailscale-router" hostConfig.roles;
in
{
  options.profiles.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN";
  };

  config = lib.mkIf cfg.enable {
    # Enable tailscale service
    services.tailscale = {
      enable = true;
      useRoutingFeatures = if isRouter then "server" else "client";
      authKeyFile = config.sops.secrets.tailscale_auth_key.path;
      extraSetFlags = lib.optionals isRouter [
        "--advertise-routes=10.10.10.0/24"
        "--accept-dns=true"
      ];
    };

    # Firewall configuration
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    # Note: tailscale_auth_key secret is defined in modules/common/sops.nix
  };
}

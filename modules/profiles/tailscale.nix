{
  lib,
  config,
  hostConfig,
  ...
}:

let
  cfg = config.profiles.tailscale;
  isRouter = builtins.elem "tailscale-router" hostConfig.roles;
  magicDnsSuffix = "tail96fefe.ts.net";
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
      extraSetFlags =
        lib.optionals isRouter [
          "--advertise-routes=10.10.10.0/24"
          "--accept-dns=false" # Routers manage their own DNS; prevents circular dependency
        ]
        ++ lib.optionals (!isRouter) [
          "--accept-dns=true"
        ];
    };

    # Firewall configuration
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    # Routers need static DNS since they don't accept Tailscale DNS
    # Uses Blocky as primary with Google/Cloudflare fallback
    networking.nameservers = lib.mkIf isRouter [
      "10.10.10.100" # Blocky (cluster DNS)
      "8.8.8.8" # Google fallback
      "1.1.1.1" # Cloudflare fallback
    ];

    # Unbound DNS forwarder for MagicDNS zone (subnet routers only)
    # Listens on port 1053 to avoid conflicts; forwards tail96fefe.ts.net to Tailscale MagicDNS
    services.unbound = lib.mkIf isRouter {
      enable = true;
      resolveLocalQueries = false; # Don't take over system DNS - we only forward MagicDNS
      settings = {
        server = {
          interface = [
            "127.0.0.1@1053"
            "${hostConfig.ipAddress}@1053"
          ];
          port = 1053;
          access-control = [
            "127.0.0.0/8 allow"
            "10.0.0.0/16 allow" # Cilium pod CIDR
            "10.10.10.0/24 allow" # LAN nodes
            "10.43.0.0/16 allow" # k8s service CIDR
          ];
          # Disable recursion - we only forward
          do-not-query-localhost = false;
        };
        forward-zone = [
          {
            name = "${magicDnsSuffix}.";
            forward-addr = "100.100.100.100@53";
          }
        ];
      };
    };

    # Note: tailscale_auth_key secret is defined in modules/common/sops.nix
  };
}

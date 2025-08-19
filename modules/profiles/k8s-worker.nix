{ lib, config, hostName, ... }:

let
  serviceEnabled = true;
  cfg = config.profiles."k8s-worker";
in
{
  options.profiles."k8s-worker" = {
    enable = lib.mkEnableOption "Enable Kubernetes worker node role";
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = serviceEnabled;
      role = "agent";
      extraFlags = toString [
        "--node-name=${hostName}"
        "--node-label=node-group=worker"
      ];
      tokenFile = config.sops.secrets.k3s_token.path;
      serverAddr = "https://${config.homelab.kubernetes.vipAddress}:6443";
    };
  };
}

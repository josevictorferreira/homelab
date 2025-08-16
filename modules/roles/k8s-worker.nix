{ lib, config, clusterConfig, hostName, ... }:

let
  cfg = config.roles.k8sWorker;
in
{
  options.roles.k8sWorker = {
    enable = lib.mkEnableOption "Enable Kubernetes worker node role";
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = "agent";
      extraFlags = toString [
        "--node-name=${hostName}"
        "--node-label=node-group=worker"
      ];
      tokenFile = config.sops.secrets.k3s_token.path;
      serverAddr = "https://${clusterConfig.ipAddress}:6443";
    };
  };
}

{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
    ./../modules/roles/k8s-worker.nix
  ];

  networking.hostName = hostName;
  networking.staticIP = {
    enable = true;
    interface = "ens18";
    address = hostConfig.ipAddress;
  };
}

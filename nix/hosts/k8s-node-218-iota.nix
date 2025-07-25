{ hostName, hostConfig, ... }:

{
  imports = [
    ./base.nix
    ./../modules/roles/k8s-worker.nix
  ];
}

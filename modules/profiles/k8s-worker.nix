{
  lib,
  config,
  hostName,
  homelab,
  hostConfig,
  ...
}:

let
  serviceEnabled = true;
  cfg = config.profiles."k8s-worker";
  amdGpuFlags = [
    "--node-label=gpu.amd.rocm=enabled"
    "--node-label=workload.gpu=true"
  ];
in
{
  options.profiles."k8s-worker" = {
    enable = lib.mkEnableOption "Enable Kubernetes worker node role";
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = serviceEnabled;
      role = "agent";
      extraFlags = toString (
        [
          "--node-name=${hostName}"
          "--node-label=node-group=worker"
          "--kubelet-arg=container-log-max-size=10Mi"
          "--kubelet-arg=container-log-max-files=3"
          "--kubelet-arg=image-gc-high-threshold=85"
          "--kubelet-arg=image-gc-low-threshold=80"
          "--kubelet-arg=eviction-hard=imagefs.available<10%,nodefs.available<5%"
          "--kubelet-arg=eviction-soft=imagefs.available<15%,nodefs.available<10%"
          "--kubelet-arg=eviction-soft-grace-period=imagefs.available=2m,nodefs.available=2m"
          "--kubelet-arg=eviction-max-pod-grace-period=30"
        ]
        ++ (if (builtins.elem "amd-gpu" hostConfig.roles) then amdGpuFlags else [ ])
      );
      tokenFile = config.sops.secrets.k3s_token.path;
      serverAddr = "https://${homelab.kubernetes.vipAddress}:6443";
    };
  };
}

{ kubenix, ... }:
{
  kubernetes = {
    helm.releases."amd-gpu-device-plugin" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://rocm.github.io/k8s-device-plugin";
        chart = "amd-gpu";
        version = "0.20.0";
        sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
      };
      namespace = "kube-system";
      includeCRDs = true;
      noHooks = true;
      values = {
        containerRuntime = "containerd";
        tolerations = [
          {
            key = "node-role.kubernetes.io/control-plane";
            operator = "Exists";
            effect = "NoSchedule";
          }
        ];

        node_selector = {
          "gpu-amd" = "enabled";
        };
      };
    };
  };
}

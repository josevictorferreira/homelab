{ kubenix, ... }:
{
  kubernetes = {
    helm.releases."amd-gpu-device-plugin" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://rocm.github.io/k8s-device-plugin";
        chart = "amd-gpu";
        version = "0.22.0";
        sha256 = "sha256-5BxV3jXmRMz8WD7WAHEtU9s4Mg3SOkd62wWVfpP6/DM=";
      };
      namespace = "kube-system";
      includeCRDs = true;
      noHooks = true;
      values = {
        tolerations = [
          {
            key = "node-role.kubernetes.io/control-plane";
            operator = "Exists";
            effect = "NoSchedule";
          }
        ];
      };
    };

    resources.daemonSets."amd-gpu-device-plugin-daemonset" = {
      spec.template.spec.nodeSelector = {
        "node.kubernetes.io/amd-gpu" = "true";
      };
    };
  };
}

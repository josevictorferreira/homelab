{ kubenix, ... }:

{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

  kubernetes = {
    helm.releases."kube-vip" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://helm.cilium.io";
          chart = "cilium";
          version = "1.18.0";
          sha256 = "sha256-3Wk4qeRkU/NgCrbilmvPIdeJVH+hvbDqbqgX5yqEjXM=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = "kube-system";
      values = {
        kubeProxyReplacement = true;
        ipam.operator.clusterPoolIPv4PodCIDRList = "10.42.0.0/16";
        socketLB.enabled = false;
        envoy.enabled = false;
        externalIPs.enabled = false;
        gatewayAPI.enabled = false;
        hubble = {
          relay.enabled = false;
          ui.enabled = false;
        };
        nodePort.enabled = true;
      };
    };

    resources = {
      apiVersion = "cilium.io/v2alpha1";
      kind = "CiliumClusterwideNetworkPolicy";
      metadata = {
        name = "lb-pool";
      };
      spec = {
        blocks = [
          {
            cidr = "10.10.10.100/32";
          }
        ];
      };
    };
  };
}

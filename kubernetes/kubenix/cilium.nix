{ kubenix, clusterConfig, ... }:

{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

  kubernetes = {
    customTypes = {
      ciliumloadbalancerippool = {
        attrName = "ciliumloadbalancerippool";
        group = "cilium.io";
        version = "v2alpha1";
        kind = "CiliumLoadBalancerIPPool";
      };
    };

    helm.releases."cilium" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://helm.cilium.io";
          chart = "cilium";
          version = "1.18.0";
          sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
        };
      includeCRDs = true;
      noHooks = true;
      values = {
        namespaceOverride = "kube-system";
        kubeProxyReplacement = true;
        k8sServiceHost = clusterConfig.ipAddress;
        k8sServicePort = 6443;
        routingMode = "native";
        ipam.operator.clusterPoolIPv4PodCIDRList = "10.42.0.0/16";
        ipv4NativeRoutingCIDR = "10.42.0.0/16";
        socketLB.enabled = false;
        envoy.enabled = false;
        externalIPs.enabled = false;
        gatewayAPI.enabled = false;
        hubble = {
          relay.enabled = false;
          ui.enabled = false;
        };
        nodePort.enabled = false;
      };
    };

    resources = {
      ciliumloadbalancerippool."lb-pool" = {
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
  };
}

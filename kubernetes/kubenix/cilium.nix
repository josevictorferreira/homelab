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
        socketLB.enabled = false;
        envoy.enabled = false;
        externalIPs.enabled = true;
        gatewayAPI.enabled = false;
        rollOutCiliumPods = true;
        operator = {
          enabled = true;
          rollOutPods = true;
          replicas = 1;
        };
        hubble = {
          relay.enabled = false;
          ui.enabled = false;
        };
        nodePort.enabled = true;
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
              start = "10.10.10.100";
              stop = "10.10.10.199";
            }
          ];
        };
      };
    };
  };
}

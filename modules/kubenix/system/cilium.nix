{ kubenix, homelab, ... }:

{
  kubernetes = {
    helm.releases."cilium" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.cilium.io";
        chart = "cilium";
        version = "1.18.7";
        sha256 = "sha256-DVvFDuFsmV5616wSO9Iiz5dFBNeCtcn7Yro9wOzeA3E";
      };
      includeCRDs = true;
      noHooks = true;
      values = {
        namespaceOverride = "kube-system";
        kubeProxyReplacement = true;
        k8sServiceHost = homelab.kubernetes.vipAddress;
        k8sServicePort = 6443;
        socketLB.enabled = false;
        envoy.enabled = false;
        gatewayAPI.enabled = false;
        rollOutCiliumPods = true;
        l2announcements.enabled = true;
        externalIPs.enabled = true;
        ingressController = {
          enabled = true;
          default = true;
          loadbalancerMode = "shared";
          service = {
            annotations = {
              "lbipam.cilium.io/ips" = homelab.kubernetes.loadBalancer.address;
              "lbipam.cilium.io/sharing-key" = "cilium-ingress";
            };
          };
        };
        k8sClientRateLimit = {
          qps = 50;
          burst = 200;
        };
        operator = {
          enabled = true;
          rollOutPods = true;
        };
        hubble = {
          enabled = false;
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
          blocks = [ homelab.kubernetes.loadBalancer.range ];
        };
      };
      ciliuml2announcementpolicy."default-l2-announcement-policy" = {
        metadata = {
          name = "default-l2-announcement-policy";
          namespace = "kube-system";
        };
        spec = {
          externalIPs = true;
          loadBalancerIPs = true;
        };
      };
    };
  };
}

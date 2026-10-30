{ kubenix, homelab, ... }:

{
  kubernetes = {
    helm.releases."cilium" = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.cilium.io";
        chart = "cilium";
        version = "1.19.10";
        sha256 = "sha256-jYWdIqH4OVoOBowWuMV1OPLd7b9Sv2D0XSJVvYY0fB0=";
      };
      includeCRDs = true;
      noHooks = true;
      values = {
        namespaceOverride = "kube-system";
        # The first Cilium minor this cluster was installed with; keeps
        # datapath defaults stable across upgrades.
        upgradeCompatibility = "1.18";
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
        # The chart default is a bare integer, which kubenix rejects for a
        # Quantity field.
        cni.resources.limits.cpu = "1";
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
          # Restrict L2/ARP announcements to the physical LAN NIC. Without this
          # Cilium may pick tailscale0 (NOARP, no MAC) and crash-loop the agent
          # with "failed to craft ARP reply packet: invalid hardware address".
          interfaces = [ "^enp1s0$" ];
          nodeSelector = {
            matchExpressions = [
              {
                key = "kubernetes.io/arch";
                operator = "In";
                values = [ "amd64" ];
              }
            ];
          };
        };
      };
    };
  };
}

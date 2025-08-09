{ kubenix, clusterConfig, ... }:

let
  controlPlaneNodeHostName = builtins.head clusterConfig.nodeGroups.k8sControlPlanes;
  controlPlaneIpAddress = clusterConfig.hosts.${controlPlaneNodeHostName}.ipAddress;
in
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
      ciliuml2announcementpolicy = {
        attrName = "ciliuml2announcementpolicy";
        group = "cilium.io";
        version = "v2alpha1";
        kind = "CiliumL2AnnouncementPolicy";
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
        k8sServiceHost = controlPlaneIpAddress;
        k8sServicePort = 6443;
        socketLB.enabled = false;
        envoy.enabled = false;
        gatewayAPI.enabled = false;
        rollOutCiliumPods = true;
        l2announcements.enabled = true;
        externalIPs.enabled = true;
        ingressController = {
          enabled = false;
          default = true;
          loadBalancerMode = "shared";
          service = {
            annotations = {
              "io.cilium/lb-ipam-ips" = clusterConfig.ingressAddress;
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
      ciliuml2announcementpolicy."default-l2-announcement-policy" = {
        metadata = {
          name = "default-l2-announcement-policy";
          namespace = "kube-system";
        };
        spec = {
          enabled = true;
          externalIPs = true;
          loadBalancerIPs = true;
        };
      };
    };
  };
}

{ kubenix, clusterConfig, ... }:

let
  mainControlPlaneHost = builtins.head clusterConfig.nodeGroups.k8sControlPlanes;
  mainControlPlaneConfig = clusterConfig.hosts.${mainControlPlaneHost};
in
{
  kubernetes.helm.releases."kube-vip" = {
    chart = kubenix.lib.helm.fetch
      {
        repo = "https://kube-vip.github.io/helm-charts";
        chart = "kube-vip";
        version = "0.7.1";
        sha256 = "sha256-3Wk4qeRkU/NgCrbilmvPIdeJVH+hvbDqbqgX5yqEjXM=";
      };
    includeCRDs = true;
    noHooks = true;
    namespace = "kube-system";
    values = {
      config.address = clusterConfig.ipAddress;
      env = {
        vip_interface = mainControlPlaneConfig.interface;
        vip_arp = "true";
        lb_enable = "true";
        lb_port = "6443";
        vip_cidr = "32";
        cp_enable = "true";
        svc_enable = "false";
        svc_election = "false";
        vip_leaderelection = "true";
        KUBEVIP_IN_CLUSTER = "false";
        KUBEVIP_KUBE_CONFIG = "/etc/rancher/k3s/k3s.yaml";
      };
    };
  };
}


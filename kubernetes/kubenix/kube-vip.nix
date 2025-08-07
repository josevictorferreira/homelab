{ kubenix, clusterConfig, ... }:

let
  mainControlPlaneHost = builtins.head clusterConfig.nodeGroups.k8sControlPlanes;
  mainControlPlaneConfig = clusterConfig.hosts.${mainControlPlaneHost};
in
{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

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
        vip_arp = true;
        lb_enable = false;
        lb_port = 6443;
        vip_cidr = 32;
        cp_enable = true;
        svc_enable = true;
        svc_election = true;
        vip_leaderelection = true;
      };
    };
  };
}

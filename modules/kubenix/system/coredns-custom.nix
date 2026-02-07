{ homelab, ... }:

{
  kubernetes.resources.configMaps.coredns-custom = {
    metadata.namespace = "kube-system";
    data = {
      # Forward all external DNS queries to Blocky instead of host resolv.conf
      # This enables pods to resolve custom domains (e.g., matrix.josevictor.me)
      # that are defined in Blocky's customDNS mapping
      "blocky.override" = ''
        forward . ${homelab.kubernetes.loadBalancer.services.blocky}
      '';
    };
  };
}

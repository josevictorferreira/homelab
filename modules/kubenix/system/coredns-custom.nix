{ homelab, ... }:

{
  kubernetes.resources.configMaps.coredns-custom = {
    metadata.namespace = "kube-system";
    data = {
      # Route *.josevictor.me (the ingress / split-horizon domain managed by
      # Blocky) to Blocky. A *.server file is imported at the top level of the
      # Corefile, creating a more-specific zone block CoreDNS matches before the
      # .:53 catch-all. The earlier blocky.override approach injected a second
      # `forward .` inside .:53, conflicting with the existing upstream forward and
      # silently never taking effect.
      "josevictor-me.server" = ''
        josevictor.me:53 {
          errors
          cache 30
          forward . ${homelab.kubernetes.loadBalancer.services.blocky}
        }
      '';
    };
  };
}

{ homelab, ... }:

let
  k8sSecretsFile = "${homelab.paths.secrets}/k8s-secrets.enc.yaml";
in
rec {
  secretsFor = secretName: "ref+sops://${k8sSecretsFile}#${secretName}";

  domainFor = serviceName: "${serviceName}.${homelab.domain}";

  serviceIpFor = serviceName: {
    "lbipam.cilium.io/ips" = homelab.kubernetes.loadBalancer.services.${serviceName};
    "lbipam.cilium.io/sharing-key" = serviceName;
  };

  plainServiceFor = serviceName: {
    enabled = true;
    type = "LoadBalancer";
    annotations = serviceIpFor serviceName;
  };

  ingressDomainFor = serviceName: {
    enabled = true;
    ingressClassName = "cilium";
    annotations = {
      "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
    };
    hosts = [
      "${serviceName}.${homelab.domain}"
    ];
    tls = [
      {
        hosts = [
          "${serviceName}.${homelab.domain}"
        ];
        secretName = "wildcard-tls";
      }
    ];
  };

  ingressDomainForService = serviceName: {
    enabled = true;
    primary = true;
    ingressClassName = "cilium";
    annotations = {
      "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
    };
    hosts = [
      { host = "${serviceName}.${homelab.domain}"; }
    ];
    tls = [
      {
        hosts = [
          "${serviceName}.${homelab.domain}"
        ];
        secretName = "wildcard-tls";
      }
    ];
  };
}

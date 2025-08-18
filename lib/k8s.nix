{ loadBalancer, domain, flakeRoot, ... }:

let
  repoPathVariableName = "HOMELAB_REPO_PATH";
  repoPathEnv = builtins.getEnv repoPathVariableName;
  repoRoot = if repoPathEnv != "" then repoPathEnv else flakeRoot;
  k8sSecretsFile = "${repoRoot}/secrets/k8s-secrets.enc.yaml";
in
rec {
  secretsFor = secretName: "ref+sops://${k8sSecretsFile}#${secretName}";

  serviceIpFor = serviceName: {
    "lbipam.cilium.io/ips" = loadBalancer.services.${serviceName};
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
      "${serviceName}.${domain}"
    ];
    tls = [
      {
        hosts = [
          "${serviceName}.${domain}"
        ];
        secretName = "wildcard-tls";
      }
    ];
  };
}

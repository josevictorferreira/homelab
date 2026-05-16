{ pkgs, homelab, ... }:

let
  k8sSecretsFile = "secrets/k8s-secrets.enc.yaml";
in
rec {
  secretsFor = secretName: "ref+sops://${k8sSecretsFile}#${secretName}";

  secretsInlineFor = secretName: "ref+sops://${k8sSecretsFile}#${secretName}+";

  domainFor = serviceName: "${serviceName}.${homelab.domain}";

  toYamlStr = data: builtins.readFile ((pkgs.formats.yaml { }).generate "." data);

  serviceHostFor = serviceName: namespace: "${serviceName}.${namespace}.svc.cluster.local";

  serviceAnnotationFor = serviceName: {
    "lbipam.cilium.io/ips" = homelab.kubernetes.loadBalancer.services.${serviceName};
    "lbipam.cilium.io/sharing-key" = serviceName;
  };

  plainServiceFor = serviceName: {
    enabled = true;
    type = "LoadBalancer";
    annotations = serviceAnnotationFor serviceName;
  };

  ingressDomainFor = serviceName: {
    enabled = true;
    ingressClassName = defaultIngressClass;
    annotations = {
      "cert-manager.io/cluster-issuer" = defaultClusterIssuer;
    };
    hosts = [
      "${serviceName}.${homelab.domain}"
    ];
    tls = [
      {
        hosts = [
          "${serviceName}.${homelab.domain}"
        ];
        secretName = defaultTLSSecret;
      }
    ];
  };

  ingressFor = serviceName: {
    enabled = true;
    ingressClassName = defaultIngressClass;
    className = defaultIngressClass;
    annotations = {
      "cert-manager.io/cluster-issuer" = defaultClusterIssuer;
    };
    hosts = [
      {
        host = domainFor serviceName;
        paths = [
          {
            path = "/";
            pathType = "Prefix";
            backend = {
              service = {
                name = serviceName;
                port.name = "http";
              };
            };
          }
        ];
      }
    ];
    tls = [
      {
        hosts = [
          (domainFor serviceName)
        ];
        secretName = defaultTLSSecret;
      }
    ];
  };

  ingressDomainForService = serviceName: {
    enabled = true;
    primary = true;
    ingressClassName = defaultIngressClass;
    annotations = {
      "cert-manager.io/cluster-issuer" = defaultClusterIssuer;
    };
    hosts = [
      { host = "${serviceName}.${homelab.domain}"; }
    ];
    tls = [
      {
        hosts = [
          "${serviceName}.${homelab.domain}"
        ];
        secretName = defaultTLSSecret;
      }
    ];
  };

  objectStoreEndpoint = "http://rook-ceph-rgw-ceph-objectstore.${homelab.kubernetes.namespaces.storage}.svc.cluster.local";

  defaultStorageClass = "rook-ceph-block";
  defaultIngressClass = "cilium";
  defaultTLSSecret = "wildcard-tls";
  defaultClusterIssuer = "cloudflare-issuer";

  nodeAffinityFor =
    appName:
    let
      cfg = homelab.kubernetes.affinity.apps.${appName} or { };
      node = cfg.node or null;
      preferred = cfg.preferred or null;
      avoid = cfg.avoid or [ ];
      requiredTerms =
        if node != null then
          [
            {
              matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "In";
                  values = [ node ];
                }
              ];
            }
          ]
        else if avoid != [ ] then
          [
            {
              matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "NotIn";
                  values = avoid;
                }
              ];
            }
          ]
        else
          [ ];
      preferredTerms =
        if preferred != null && node == null then
          [
            {
              weight = 100;
              preference.matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "In";
                  values = [ preferred ];
                }
              ];
            }
          ]
        else
          [ ];
    in
    (pkgs.lib.optionalAttrs (requiredTerms != [ ]) {
      requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = requiredTerms;
    })
    // (pkgs.lib.optionalAttrs (preferredTerms != [ ]) {
      preferredDuringSchedulingIgnoredDuringExecution = preferredTerms;
    });

  sharedStorage = {
    rootPVC = "cephfs-shared-storage-root";
    downloadsPVC = "cephfs-shared-storage-downloads";
  };
}

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

  # Bucket policy for OBC-provisioned RGW buckets: lets the shared `s3-user`
  # (used by the rgw-mirror CronJob) read the bucket so it can be backed up.
  # Pass via `spec.additionalConfig.bucketPolicy`.
  rgwMirrorReadPolicyFor = bucket: builtins.toJSON {
    Version = "2012-10-17";
    Statement = [
      {
        Sid = "rgw-mirror-read";
        Effect = "Allow";
        Principal.AWS = [ "arn:aws:iam:::user/s3-user" ];
        Action = [ "s3:ListBucket" "s3:GetObject" ];
        Resource = [ "arn:aws:s3:::${bucket}" "arn:aws:s3:::${bucket}/*" ];
      }
    ];
  };

  plainServiceFor = serviceName: {
    enabled = true;
    type = "LoadBalancer";
    annotations = serviceAnnotationFor serviceName;
  };

  ingressDomainFor = serviceName: {
    enabled = true;
    ingressClassName = defaultIngressClass;
    annotations = { };
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
    annotations = { };
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
    annotations = { };
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
  # Ingresses using defaultTLSSecret must NOT carry a cert-manager.io/cluster-issuer
  # annotation: system/cert-manager.nix already issues `wildcard-certificate` into
  # this secret in every namespace. The annotation makes ingress-shim create a second
  # Certificate for the same secret, and the two fight ("IncorrectCertificate: Secret
  # was issued for ..."). Apps with their own TLS secret annotate their ingress inline.
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

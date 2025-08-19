{ labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    namespace = namespace;
    resources = {
      certificate."wildcard-certificate" = {
        metadata = {
          name = "wildcard-certificate";
          namespace = namespace;
          annotations = {
            "cert-manager.io/issue-temporary-certificate" = "true";
          };
        };
        spec = {
          secretName = "wildcard-tls";
          issuerRef = {
            name = "cloudflare-issuer";
            kind = "ClusterIssuer";
          };
          dnsNames = [
            "${labConfig.cluster.domain}"
            "*.${labConfig.cluster.domain}"
          ];
        };
      };
    };
  };
}

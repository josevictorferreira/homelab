{ labConfig, ... }:

let
  namespace = labConfig.kubernetes.namespaces.monitoring;
in
{
  kubernetes = {
    namespace = namespace;
    customTypes = {
      certificate = {
        attrName = "certificate";
        group = "cert-manager.io";
        version = "v1";
        kind = "Certificate";
      };
    };
    resources = {
      namespaces.${namespace} = {
        metadata = {
          name = namespace;
        };
      };

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

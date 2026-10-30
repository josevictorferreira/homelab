{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.certificate;
  namespacesList = builtins.attrValues homelab.kubernetes.namespaces;
  certificatesResources = builtins.map
    (namespace: {
      name = "${namespace}-wildcard-certificate";
      value = {
        metadata = {
          name = "wildcard-certificate";
          inherit namespace;
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
            "${homelab.domain}"
            "*.${homelab.domain}"
          ];
        };
      };
    })
    namespacesList;
in
{
  kubernetes = {
    helm.releases."cert-manager" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.jetstack.io";
          chart = "cert-manager";
          version = "1.19.6";
          sha256 = "sha256-ZxVc2Ch5S72/CmGCZVsx+l4iYklx4cNkIEryV411F5I=";
        };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;
      values = {
        global.leaderElection.namespace = homelab.kubernetes.namespaces.certificate;
        crds.enabled = true;
        prometheus.enabled = false;
      };
    };

    resources = {
      clusterissuer."cloudflare-issuer" = {
        metadata = {
          name = "cloudflare-issuer";
          inherit namespace;
        };
        spec = {
          acme = {
            server = "https://acme-v02.api.letsencrypt.org/directory";
            privateKeySecretRef = {
              name = "cloudflare-issuer-account-key";
            };
            solvers = [
              {
                dns01 = {
                  cloudflare = {
                    apiTokenSecretRef = {
                      name = "cloudflare-api-token";
                      key = "cloudflare-api-token";
                    };
                  };
                };
              }
            ];
          };
        };
      };

      certificate = builtins.listToAttrs certificatesResources;
    };
  };
}

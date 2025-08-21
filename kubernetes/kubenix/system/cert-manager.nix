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
          version = "1.18.2";
          sha256 = "sha256-vwe9ARF8VZ+Ntl1IR4TyNAXNmZU9+TNVVsnC+s+ZjQ0=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        global.leaderElection.namespace = "cert-manager";
        crds.enabled = true;
        prometheus.enabled = false;
      };
    };

    resources = {
      clusterissuer."cloudflare-issuer" = {
        metadata = {
          name = "cloudflare-issuer";
          namespace = namespace;
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

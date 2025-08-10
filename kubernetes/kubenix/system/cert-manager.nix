{ kubenix, clusterConfig, ... }:

let
  namespace = "cert-manager";
in
{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

  kubernetes = {
    customTypes = {
      clusterissuer = {
        attrName = "clusterissuer";
        group = "cert-manager.io";
        version = "v1";
        kind = "ClusterIssuer";
      };
    };

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
    };
  };
}

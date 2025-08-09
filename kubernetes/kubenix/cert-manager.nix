{ kubenix, ... }:

let
  namespace = "cert-manager";
  certificateNamespaces = [
    "apps"
    "monitoring"
  ];
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
      certificate = {
        attrName = "certificate";
        group = "cert-manager.io";
        version = "v1";
        kind = "Certificate";
      };
    };

    helm.releases."cert-manager" = {
      chart = kubenix.lib.helm.fetch
        {
          repo = "https://charts.jetstack.io";
          chart = "cert-manager";
          version = "1.18.2";
          sha256 = "sha256-km3mRsCk7NpbTJ8l8C52eweF+u9hqxIhEWALQ8LqN+0=";
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

      certificate = builtins.listToAttrs (map
        (nms: {
          name = "self-signed-ca-${nms}";
          value = {
            metadata = {
              name = "self-signed-ca";
              namespace = nms;
            };
            spec = {
              isCA = true;
              commonName = "My Root CA";
              secretName = "self-signed-ca";
              duration = "8760h"; # 1 year
              renewBefore = "360h"; # 15 days
              privateKey = {
                algorithm = "RSA";
                size = 2048;
              };
            };
          };
        })
        certificateNamespaces);
    };
  };
}

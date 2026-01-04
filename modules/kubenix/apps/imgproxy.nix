{ kubenix, homelab, ... }:

let
  app = "imgproxy";
  bucketName = "imgproxy";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://helm.imgproxy.net/";
        chart = "imgproxy";
        version = "1.1.0";
        sha256 = "sha256-y6quMzOF1ekDrdgxOOGb90Cq2lDVus281+GfF8mU4bc=";
      };
      includeCRDs = true;
      noHooks = false;
      namespace = namespace;

      values = {
        image = {
          repo = "ghcr.io/imgproxy/imgproxy";
          tag = "v3.30.1@sha256:3b709e4a0e5e8e0e959b556b7031229202b4b8e7e7d955c517ea7abed68ee34d";
        };

        resources.addSecrets = [
          "imgproxy-config"
          "imgproxy-s3"
        ];

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          hosts = [
            {
              host = kubenix.lib.domainFor app;
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [
                (kubenix.lib.domainFor app)
              ];
              secretName = "wildcard-tls";
            }
          ];
        };
      };
    };

    resources.objectbucketclaim."imgproxy-s3" = {
      metadata = {
        namespace = namespace;
      };
      spec = {
        bucketName = bucketName;
        storageClassName = "rook-ceph-objectstore";
      };
    };
  };
}

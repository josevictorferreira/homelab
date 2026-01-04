{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."gluetun-vpn-credentials" = {
        metadata = {
          name = "gluetun-vpn-credentials";
          namespace = namespace;
        };
        data = {
          "IMGPROXY_USE_S3" = "true";
          "IMGPROXY_S3_REGION" = "us-east-1";
          "IMGPROXY_S3_ENDPOINT" = "http://rook-ceph-rgw-ceph-objectstore.${homelab.kubernetes.namespaces.storage}.svc.cluster.local";
          "IMGPROXY_S3_ENDPOINT_USE_PATH_STYLE" = "true";
          "IMGPROXY_KEY" = kubenix.lib.secretsFor "imgproxy_key";
          "IMGPROXY_SALT" =  kubenix.lib.secretsFor "imgproxy_salt";
          "IMGPROXY_SIGNATURE_SIZE" = "32";
        };
      };
    };
  };
}

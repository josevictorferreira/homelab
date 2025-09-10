{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."s3-credentials" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "AWS_ACCESS_KEY_ID" = kubenix.lib.secretsFor "ceph_objectstore_access_key_id";
          "AWS_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "ceph_objectstore_secret_access_key";
        };
      };

      cephobjectstoreuser."s3-user" = {
        metadata.namespace = namespace;

        spec = {
          store = "ceph-objectstore";
          clusterNamespace = homelab.kubernetes.namespaces.storage;
          keys = [
            {
              accessKeyRef = {
                name = "s3-credentials";
                key = "AWS_ACCESS_KEY_ID";
              };
              secretKeyRef = {
                name = "s3-credentials";
                key = "AWS_SECRET_ACCESS_KEY";
              };
            }
          ];
        };
      };
    };
  };
}

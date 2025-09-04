{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    resources = {
      secrets."ceph-object-store-credentials" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          "AccessKey" = kubenix.lib.secretsFor "ceph_object_store_access_key";
          "SecretKey" = kubenix.lib.secretsFor "ceph_object_store_secret_key";
          "accessKey" = kubenix.lib.secretsFor "ceph_object_store_access_key";
          "secretKey" = kubenix.lib.secretsFor "ceph_object_store_secret_key";
        };
      };
      cephobjectstoreuser."homelab-user" = {
        metadata = {
          namespace = namespace;
        };
        spec = {
          store = "homelab-store";
          displayName = "Homelab Client";
          credentials.name = "ceph-object-store-credentials";
        };
      };
    };
  };
}

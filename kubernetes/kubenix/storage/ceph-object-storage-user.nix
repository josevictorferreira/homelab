{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    resources = {
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

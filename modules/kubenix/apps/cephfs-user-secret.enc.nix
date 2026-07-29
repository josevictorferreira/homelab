{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."cephfs-user-secret" = {
        metadata = { inherit namespace; };
        data = {
          "userID" = kubenix.lib.secretsFor "cephfs_user_id";
          "userKey" = kubenix.lib.secretsFor "cephfs_user_key";
        };
      };
    };
  };
}

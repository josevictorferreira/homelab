{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    resources = {
      secrets."cephfs-user-secret" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          "userID" = kubenix.lib.secretsFor "cephfs_user_id";
          "userKey" = kubenix.lib.secretsFor "cephfs_user_key";
        };
      };

      secrets."cephfs-smb-export-credentials" = {
        type = "Opaque";
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "SAMBA_USERS" = kubenix.lib.secretsFor "smb_users";
          "SAMBA_SHARES" = "cephfs;/export;yes;yes;no;homelab";
        };
      };
    };
  };
}

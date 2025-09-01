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
        stringData = {
          "userID" = kubenix.lib.secretsFor "cephfs_user_id";
          "userKey" = kubenix.lib.secretsFor "cephfs_user_key";
        };
      };

      secrets."smb-export-credentials" = {
        type = "Opaque";
        metadata = {
          namespace = namespace;
        };
        data = {
          "username" = kubenix.lib.secretsFor "smb_export_username";
          "password" = kubenix.lib.secretsFor "smb_export_password";
        };
      };
    };
  };
}

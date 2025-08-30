{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes = {
    resources = {
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

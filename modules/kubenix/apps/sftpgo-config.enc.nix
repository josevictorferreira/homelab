{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."sftpgo-config" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "SFTPGO_ADMIN_USERNAME" = "admin";
          "SFTPGO_ADMIN_PASSWORD" = kubenix.lib.secretsFor "sftpgo_admin_password";
        };
      };
    };
  };
}

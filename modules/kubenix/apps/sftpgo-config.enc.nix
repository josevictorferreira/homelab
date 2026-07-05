{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."sftpgo-config" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "SFTPGO_ADMIN_USERNAME" = "admin";
          "SFTPGO_ADMIN_PASSWORD" = kubenix.lib.secretsFor "sftpgo_admin_password";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__CLIENT_ID" = "sftpgo";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__CLIENT_SECRET" =
            kubenix.lib.secretsFor "sftpgo_oidc_client_secret";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__CONFIG_URL" = "https://identity.${homelab.domain}/realms/homelab";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__REDIRECT_BASE_URL" = "https://sftpgo.${homelab.domain}";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__USERNAME_FIELD" = "preferred_username";
          "SFTPGO_HTTPD__BINDINGS__0__OIDC__SCOPES" = "openid,profile,email";
        };
      };
    };
  };
}

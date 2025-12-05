{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."valoris-config" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "RAILS_LOG_TO_STDOUT" = "true";
          "RAILS_ENV" = "true";
          "VALORIS_DATABASE_HOST" = "postgresql-hl";
          "VALORIS_DATABASE_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
        };
      };
    };
  };
}

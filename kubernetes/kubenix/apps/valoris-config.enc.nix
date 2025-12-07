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
          "RAILS_ENV" = "production";
          "VALORIS_DATABASE_HOST" = "postgresql-hl";
          "VALORIS_DATABASE_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
          "VALORIS_JOBS_UI_USERNAME" = kubenix.lib.secretsFor "valoris_jobs_ui_username";
          "VALORIS_JOBS_UI_PASSWORD" = kubenix.lib.secretsFor "valoris_jobs_ui_password";
          "VALORIS_RES_BROWSER_USERNAME" = kubenix.lib.secretsFor "valoris_res_browser_username";
          "VALORIS_RES_BROWSER_PASSWORD" = kubenix.lib.secretsFor "valoris_res_browser_password";
          "SECRET_KEY_BASE" = kubenix.lib.secretsFor "valoris_secret_key_base";
        };
      };
    };
  };
}

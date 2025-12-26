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
          "LOG_LEVEL" = "DEBUG";
          "RAILS_ENV" = "production";
          "VALORIS_DATABASE_HOST" = "postgresql-18-hl";
          "VALORIS_DATABASE_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
          "VALORIS_JOBS_UI_USERNAME" = kubenix.lib.secretsFor "valoris_jobs_ui_username";
          "VALORIS_JOBS_UI_PASSWORD" = kubenix.lib.secretsFor "valoris_jobs_ui_password";
          "VALORIS_RES_BROWSER_USERNAME" = kubenix.lib.secretsFor "valoris_res_browser_username";
          "VALORIS_RES_BROWSER_PASSWORD" = kubenix.lib.secretsFor "valoris_res_browser_password";
          "SECRET_KEY_BASE" = kubenix.lib.secretsFor "valoris_secret_key_base";
          "S3_ENDPOINT" =
            "http://rook-ceph-rgw-ceph-objectstore.${homelab.kubernetes.namespaces.storage}.svc.cluster.local";
          "S3_BUCKET" = "valoris-s3";
        };
      };
    };
  };
}

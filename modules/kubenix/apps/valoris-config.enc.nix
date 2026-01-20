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
          "S3_PUBLIC_ENDPOINT" = "https://objectstore.josevictor.me";
          "S3_BUCKET" = "valoris-s3";
          "IMGPROXY_ENDPOINT" = "https://${kubenix.lib.domainFor "imgproxy"}";
          "IMGPROXY_KEY" = kubenix.lib.secretsFor "imgproxy_key";
          "IMGPROXY_SALT" = kubenix.lib.secretsFor "imgproxy_salt";
          "LLM_PROVIDER" = "openrouter";
          "LLM_BASE_URL" = "https://openrouter.ai/api/v1/chat/completions";
          "LLM_API_KEY" = kubenix.lib.secretsFor "openrouter_api_key_valoris";
          "LLM_MODEL" = "mistralai/mistral-small-3.1-24b-instruct";
          "LLM_TIMEOUT_SECONDS" = "180";
          "LLM_MAX_RETRIES" = "3";
          "LLM_FALLBACK_BASE_URL" = "https://openrouter.ai/api/v1/chat/completions";
          "LLM_FALLBACK_API_KEY" = kubenix.lib.secretsFor "openrouter_api_key_valoris";
          "LLM_FALLBACK_MODEL" = "mistralai/mistral-small-3.2-24b-instruct";
        };
      };
    };
  };
}

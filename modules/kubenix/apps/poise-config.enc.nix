{ kubenix, homelab, ... }:

let
  app = "poise";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # secret_key_base ships inside the image via config/credentials.yml.enc +
  # config/master.key, so it is deliberately absent here.
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      # config/database.yml derives the cache, queue, and cable database names
      # from POISE_DATABASE_NAME by suffix, so all four must exist in
      # homelab.kubernetes.databases.postgres.
      POISE_DATABASE_HOST = "postgresql-18-hl";
      POISE_DATABASE_PORT = "5432";
      POISE_DATABASE_NAME = "${app}_production";
      POISE_DATABASE_USER = "postgres";
      POISE_DATABASE_PASSWORD = kubenix.lib.secretsFor "postgresql_admin_password";

      # Chat, vision, and embeddings all go through Velox. The app appends
      # /v1/chat/completions, /v1/embeddings, and /v1/models to this base.
      LLM_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080";
      LLM_API_KEY = kubenix.lib.secretsFor "velox_api_keys";

      # Photos live in the Ceph RGW bucket provisioned by the poise-s3
      # ObjectBucketClaim; the credentials come from that claim's Secret.
      S3_ENDPOINT = kubenix.lib.objectStoreEndpoint;
      S3_BUCKET = app;
      S3_REGION = "us-east-1";

      # Basic auth in front of the Solid Queue monitor mounted at /jobs.
      JOBS_USER = kubenix.lib.secretsFor "poise_jobs_ui_username";
      JOBS_PASSWORD = kubenix.lib.secretsFor "poise_jobs_ui_password";
    };
  };
}

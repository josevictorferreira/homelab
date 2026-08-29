{ kubenix, homelab, ... }:

let
  app = "domus";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      # Database connection for the Domus Rails app (multi-db: primary/cache/queue/cable).
      DOMUS_DATABASE_HOST = "postgresql-18-hl";
      DOMUS_DATABASE_PORT = "5432";
      DOMUS_DATABASE_USERNAME = "postgres";
      DOMUS_DATABASE_PASSWORD = kubenix.lib.secretsFor "postgresql_admin_password";
      SECRET_KEY_BASE = kubenix.lib.secretsFor "domus_secret_key_base";

      # Object storage (Ceph RGW via the domus-s3 ObjectBucketClaim; keys come
      # from that claim's Secret) and imgproxy for display images.
      S3_ENDPOINT = kubenix.lib.objectStoreEndpoint;
      S3_BUCKET = "${app}-s3";
      S3_REGION = "us-east-1";
      IMGPROXY_ENDPOINT = "https://${kubenix.lib.domainFor "imgproxy"}";
      IMGPROXY_KEY = kubenix.lib.secretsFor "imgproxy_key";
      IMGPROXY_SALT = kubenix.lib.secretsFor "imgproxy_salt";

      # Image generation goes through Velox (in-cluster).
      DOMUS_VELOX_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080";
      DOMUS_VELOX_API_KEY = kubenix.lib.secretsFor "velox_api_keys";
      DOMUS_VELOX_IMAGE_MODEL = "hidream";
    };
  };
}

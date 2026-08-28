{ kubenix, homelab, ... }:
let
  app = "ideator";
  namespace = homelab.kubernetes.namespaces.applications;
  dbHost = "postgresql-18-hl";
  dbPort = "5432";
  dbUser = "postgres";
  dbPassword = kubenix.lib.secretsInlineFor "postgresql_admin_password";
in
{
  # Rails multi-DB: DATABASE_URL covers primary; the queue and cable
  # connections derive from it per connection name.
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      DATABASE_URL = "postgresql://${dbUser}:${dbPassword}@${dbHost}:${dbPort}/ideator_production";
      QUEUE_DATABASE_URL = "postgresql://${dbUser}:${dbPassword}@${dbHost}:${dbPort}/ideator_production_queue";
      CABLE_DATABASE_URL = "postgresql://${dbUser}:${dbPassword}@${dbHost}:${dbPort}/ideator_production_cable";
      # Chat goes through the in-cluster Velox LLM gateway (OpenAI-compatible);
      # the initializer reads OMNIROUTE_* names by default, no code change needed.
      OMNIROUTE_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080/v1";
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "velox_api_keys";
      # Embeddings sidecar: Velox serves voyage-3 (1024 dims, matches the
      # embedding vector columns).
      EMBEDDINGS_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080/v1";
      SECRET_KEY_BASE = kubenix.lib.secretsFor "ideator_secret_key_base";
    };
  };
}


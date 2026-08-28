{ kubenix, homelab, ... }:

let
  app = "glyph";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # Secret key base and credentials can be loaded via environment or master.key.
  # Database and API base URLs/keys are supplied here.
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      # Database connection for Glyph Rails app
      GLYPH_DATABASE_HOST = "postgresql-18-hl";
      GLYPH_DATABASE_PORT = "5432";
      GLYPH_DATABASE_NAME = "${app}_production";
      GLYPH_DATABASE_USER = "postgres";
      GLYPH_DATABASE_PASSWORD = kubenix.lib.secretsFor "postgresql_admin_password";

      # LLM provider endpoints and API keys
      VELOX_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080/v1";
      VELOX_API_KEY = kubenix.lib.secretsFor "velox_api_keys";
      OMNIROUTE_BASE_URL = "http://${kubenix.lib.serviceHostFor "omniroute" namespace}:8080/v1";
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "omniroute_api_key";
    };
  };
}

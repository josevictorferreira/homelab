{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."dramaturge-config" = {
    metadata = {
      name = "dramaturge-config";
      inherit namespace;
    };
    stringData = {
      DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl:5432/dramaturge";
      # Velox is the default LLM provider (combo glm-5-3); the base URL and
      # key mirror how poise talks to the in-cluster Velox service.
      VELOX_API_KEY = kubenix.lib.secretsFor "velox_api_keys";
      VELOX_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080/v1";
    };
  };
}

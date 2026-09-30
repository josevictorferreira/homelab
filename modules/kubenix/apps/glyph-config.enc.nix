{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."glyph-config" = {
    metadata = {
      name = "glyph-config";
      inherit namespace;
    };
    stringData = {
      # Migrations are embedded and applied at boot against a fresh `glyph`
      # database; the Rails glyph_production* databases are left untouched.
      # The URL embeds the superuser password, hence this .enc.nix file.
      DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@${kubenix.lib.postgresHost}:5432/glyph";
      # AES-256-GCM key (base64 of 32 bytes) for evidence encryption at rest.
      GLYPH_ENCRYPTION_KEY = kubenix.lib.secretsFor "glyph_encryption_key";
      # Model providers, reached over the cluster network.
      VELOX_BASE_URL = "http://${kubenix.lib.serviceHostFor "velox" namespace}:8080/v1";
      VELOX_API_KEY = kubenix.lib.secretsFor "velox_api_keys";
      OMNIROUTE_BASE_URL = "http://${kubenix.lib.serviceHostFor "omniroute" namespace}:20128/v1";
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "omniroute_api_key";
      # The browser talks to the backend through the frontend's own origin
      # (nginx proxies gRPC-Web), so only the public origin must pass CORS.
      GLYPH_CORS_ORIGINS = "https://glyph.${homelab.domain}";
      GLYPH_PUBLIC_URL = "https://glyph.${homelab.domain}";
      GLYPH_LOG_JSON = "true";
    };
  };
}

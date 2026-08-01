{ kubenix, homelab, ... }:

let
  app = "wealtho";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      WEALTHO_DATABASE_HOST = "postgresql-18-hl";
      WEALTHO_DATABASE_PORT = "5432";
      WEALTHO_DATABASE_USERNAME = "postgres";
      WEALTHO_DATABASE_PASSWORD = kubenix.lib.secretsInlineFor "postgresql_admin_password";
      SECRET_KEY_BASE = kubenix.lib.secretsFor "wealtho_secret_key_base";
    };
  };
}

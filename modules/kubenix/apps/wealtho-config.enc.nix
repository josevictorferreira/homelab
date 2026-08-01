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
      DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl:5432/wealtho";
      SECRET_KEY_BASE = kubenix.lib.secretsFor "wealtho_secret_key_base";
    };
  };
}

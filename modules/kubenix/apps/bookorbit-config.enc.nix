{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."bookorbit-config" = {
    metadata = {
      name = "bookorbit-config";
      inherit namespace;
    };
    stringData = {
      DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl:5432/bookorbit";
      JWT_SECRET = kubenix.lib.secretsFor "bookorbit_jwt_secret";
      SETUP_BOOTSTRAP_TOKEN = kubenix.lib.secretsFor "bookorbit_setup_bootstrap_token";
    };
  };
}

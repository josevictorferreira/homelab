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
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "omniroute_api_key";
      OMNIROUTE_BASE_URL = "http://omniroute.apps.svc.cluster.local:20128/v1";
      OMNIROUTE_MODEL = "pippin";
    };
  };
}
